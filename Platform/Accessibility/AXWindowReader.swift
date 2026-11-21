import AppKit
import ApplicationServices
import CoreGraphics
import Darwin
import Foundation

enum AXWindowTitleRead: Equatable {
    case value(String)
    case empty
    case unread(AXError)

    var title: String? {
        if case .value(let title) = self { return title }
        return nil
    }

    func resolvedTitle(previousTitle: String? = nil) -> String {
        switch self {
        case .value(let title): return title
        case .empty: return ""
        case .unread: return previousTitle ?? ""
        }
    }

    static func classify(result: AXError, value: CFTypeRef?) -> Self {
        switch result {
        case .success:
            guard let text = value as? String else { return .unread(.failure) }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? .empty : .value(trimmed)
        case .attributeUnsupported, .noValue:
            return .empty
        default:
            return .unread(result)
        }
    }
}

struct AXWindowSnapshot {
    let pid: Int32
    let cgWindowID: UInt32?
    let titleRead: AXWindowTitleRead
    let bounds: CGRect?
    let role: String?
    let subrole: String?
    let isMinimized: Bool
    let isFocusedWindow: Bool
    let element: AXUIElement

    var title: String? { titleRead.title }
}

struct AXWindowTarget {
    let pid: Int32
    let title: String?
    let bounds: CGRect?
}

struct AXWindowHandle {
    let pid: Int32
    let title: String?
    let bounds: CGRect?
    let element: AXUIElement
}

enum AXWindowFrameAttribute: Equatable {
    case position
    case size
}

enum AXWindowAttributeSettableStatus: Equatable {
    case settable
    case notSettable
    case unread(AXError)

    var isSettable: Bool {
        if case .settable = self { return true }
        return false
    }
}

struct AXWindowFrameSettableStatus: Equatable {
    let position: AXWindowAttributeSettableStatus
    let size: AXWindowAttributeSettableStatus

    var canSetSize: Bool { size.isSettable }
    var canSetFrame: Bool { position.isSettable && size.isSettable }
}

enum AXWindowFrameWriteFailure: Error, Equatable {
    case invalidGeometry
    case initialFrameUnavailable
    case initialFrameMismatch(expected: CGRect, actual: CGRect)
    case capabilityQueryFailed(attribute: AXWindowFrameAttribute, error: AXError)
    case attributeNotSettable(AXWindowFrameAttribute)
    case valueCreationFailed(AXWindowFrameAttribute)
    case writeFailed(attribute: AXWindowFrameAttribute, error: AXError)
    case verificationUnavailable
    case verificationMismatch(expected: CGRect, actual: CGRect)

    fileprivate var mayHaveMutatedWindow: Bool {
        switch self {
        case .writeFailed, .verificationUnavailable, .verificationMismatch:
            return true
        case .invalidGeometry,
             .initialFrameUnavailable,
             .initialFrameMismatch,
             .capabilityQueryFailed,
             .attributeNotSettable,
             .valueCreationFailed:
            return false
        }
    }
}

enum AXWindowFrameRollbackResult: Equatable {
    case notRequested
    case restored(actualFrame: CGRect)
    case failed(reason: AXWindowFrameWriteFailure, actualFrame: CGRect?)
}

enum AXWindowFrameWriteResult: Equatable {
    case success(actualFrame: CGRect)
    case failure(reason: AXWindowFrameWriteFailure, rollback: AXWindowFrameRollbackResult)
}

enum AXWindowReadResult {
    case success([AXWindowSnapshot])
    case unread(AXError)

    var windowsOrEmpty: [AXWindowSnapshot] {
        switch self {
        case .success(let windows): return windows
        case .unread: return []
        }
    }

    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}

protocol AppTrackerWindowReading: Sendable {
    func windows(forPID pid: pid_t) -> [AXWindowSnapshot]
    func windowReadResult(forPID pid: pid_t) -> AXWindowReadResult
    func inventoryWindows(forPID pid: pid_t, messagingTimeout: TimeInterval) -> AXWindowReadResult
}

struct AXWindowReader: AppTrackerWindowReading, Sendable {
    func windows(for app: NSRunningApplication) -> [AXWindowSnapshot] {
        windows(forPID: app.processIdentifier)
    }

    func windows(forPID pid: pid_t) -> [AXWindowSnapshot] {
        windowReadResult(forPID: pid).windowsOrEmpty
    }

    /// Same untimed/two-attempt read used by `windows(forPID:)`, with the read outcome preserved
    /// for diagnostics. Callers must keep mapping `.unread` to the same empty array for behavior.
    /// **Untimed = system default AX timeout (~6s) × 2 attempts. Never call this on the main actor**;
    /// `AppTracker` reaches it only on the `DOCK_EVENT_AX_ASYNC=0` / `DOCK_RECONCILE_AX_TIMEOUT_MS=0`
    /// compatibility paths. Event and poll reads use `inventoryWindows(forPID:messagingTimeout:)`.
    func windowReadResult(forPID pid: pid_t) -> AXWindowReadResult {
        readWindows(forPID: pid, messagingTimeout: nil)
    }

    func inventoryWindows(for app: NSRunningApplication, messagingTimeout: TimeInterval) -> AXWindowReadResult {
        readWindows(forPID: app.processIdentifier, messagingTimeout: messagingTimeout)
    }

    func inventoryWindows(forPID pid: pid_t, messagingTimeout: TimeInterval) -> AXWindowReadResult {
        readWindows(forPID: pid, messagingTimeout: messagingTimeout)
    }

    private func readWindows(forPID pid: pid_t, messagingTimeout: TimeInterval?) -> AXWindowReadResult {
        let appElement = AXUIElementCreateApplication(pid)
        applyMessagingTimeout(messagingTimeout, to: appElement)

        var rawWindows: CFTypeRef?
        let maxAttempts = messagingTimeout == nil ? 2 : 1
        let result = copyAttributeValue(
            kAXWindowsAttribute as CFString,
            from: appElement,
            into: &rawWindows,
            maxAttempts: maxAttempts
        )
        guard result == .success, let elements = rawWindows as? [AXUIElement] else {
            return .unread(result)
        }

        let focusedElement = elementAttribute(kAXFocusedWindowAttribute as CFString, from: appElement)
        return .success(elements.map { element in
            applyMessagingTimeout(messagingTimeout, to: element)
            return AXWindowSnapshot(
                pid: pid,
                cgWindowID: cgWindowID(for: element, maxAttempts: maxAttempts),
                titleRead: titleAttribute(from: element, maxAttempts: maxAttempts),
                bounds: frame(of: element, maxAttempts: maxAttempts),
                role: stringAttribute(kAXRoleAttribute as CFString, from: element, maxAttempts: maxAttempts),
                subrole: stringAttribute(kAXSubroleAttribute as CFString, from: element, maxAttempts: maxAttempts),
                isMinimized: boolAttribute(kAXMinimizedAttribute as CFString, from: element, maxAttempts: maxAttempts) ?? false,
                isFocusedWindow: focusedElement.map { CFEqual($0, element) } ?? false,
                element: element
            )
        })
    }

    func captureHandle(
        for target: AXWindowTarget,
        attempts: Int = 1,
        retryIntervalMicroseconds: useconds_t = 0,
        messagingTimeout: TimeInterval? = nil
    ) -> AXWindowHandle? {
        guard AXIsProcessTrusted() else { return nil }
        let boundedAttempts = max(1, attempts)

        for attempt in 0..<boundedAttempts {
            let candidates: [AXWindowSnapshot]
            if let timeout = messagingTimeout {
                switch inventoryWindows(forPID: target.pid, messagingTimeout: timeout) {
                case .success(let s): candidates = s
                case .unread: candidates = []
                }
            } else {
                candidates = windows(forPID: target.pid)
            }
            if let snapshot = bestMatch(for: target, from: candidates) {
                return AXWindowHandle(
                    pid: target.pid,
                    title: snapshot.title,
                    bounds: snapshot.bounds,
                    element: snapshot.element
                )
            }

            if attempt < boundedAttempts - 1, retryIntervalMicroseconds > 0 {
                usleep(retryIntervalMicroseconds)
            }
        }

        return nil
    }

    func captureHandle(
        forPID pid: pid_t,
        cgWindowID: CGWindowID,
        messagingTimeout: TimeInterval = 0.1
    ) -> AXWindowHandle? {
        guard AXIsProcessTrusted(),
              cgWindowID != 0,
              messagingTimeout.isFinite,
              messagingTimeout > 0 else {
            return nil
        }

        let deadline = ProcessInfo.processInfo.systemUptime + messagingTimeout
        let appElement = AXUIElementCreateApplication(pid)

        func remainingTimeout() -> TimeInterval? {
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            return remaining > 0 ? remaining : nil
        }

        func matches(_ element: AXUIElement) -> Bool {
            guard let timeout = remainingTimeout() else { return false }
            applyMessagingTimeout(timeout, to: element)
            if let bridgedID = AXWindowIDBridge.cgWindowID(for: element) {
                return bridgedID == cgWindowID
            }

            for attribute in AXWindowIDBridge.fallbackAttributeNames {
                guard let timeout = remainingTimeout() else { return false }
                applyMessagingTimeout(timeout, to: element)
                if numericWindowIDAttribute(attribute, from: element, maxAttempts: 1) == cgWindowID {
                    return true
                }
            }
            return false
        }

        func elementAttributeWithinDeadline(_ attribute: CFString) -> AXUIElement? {
            guard let timeout = remainingTimeout() else { return nil }
            applyMessagingTimeout(timeout, to: appElement)
            return elementAttribute(attribute, from: appElement, maxAttempts: 1)
        }

        if let focused = elementAttributeWithinDeadline(kAXFocusedWindowAttribute as CFString),
           matches(focused) {
            return AXWindowHandle(pid: pid, title: nil, bounds: nil, element: focused)
        }
        if let main = elementAttributeWithinDeadline(kAXMainWindowAttribute as CFString),
           matches(main) {
            return AXWindowHandle(pid: pid, title: nil, bounds: nil, element: main)
        }

        guard let timeout = remainingTimeout() else { return nil }
        applyMessagingTimeout(timeout, to: appElement)
        var rawWindows: CFTypeRef?
        guard copyAttributeValue(
            kAXWindowsAttribute as CFString,
            from: appElement,
            into: &rawWindows,
            maxAttempts: 1
        ) == .success,
              let elements = rawWindows as? [AXUIElement],
              let element = elements.first(where: matches) else {
            return nil
        }

        return AXWindowHandle(
            pid: pid,
            title: nil,
            bounds: nil,
            element: element
        )
    }

    func focusedWindow(forPID pid: pid_t) -> AXUIElement? {
        elementAttribute(kAXFocusedWindowAttribute as CFString, from: AXUIElementCreateApplication(pid))
    }

    func stringAttribute(_ attribute: CFString, from element: AXUIElement, maxAttempts: Int = 2) -> String? {
        guard let value = copyAttributeValue(attribute, from: element, maxAttempts: maxAttempts),
              let text = value as? String else {
            return nil
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func titleAttribute(from element: AXUIElement, maxAttempts: Int = 2) -> AXWindowTitleRead {
        var value: CFTypeRef?
        let result = copyAttributeValue(
            kAXTitleAttribute as CFString,
            from: element,
            into: &value,
            maxAttempts: maxAttempts
        )
        return AXWindowTitleRead.classify(result: result, value: value)
    }

    func boolAttribute(_ attribute: CFString, from element: AXUIElement, maxAttempts: Int = 2) -> Bool? {
        guard let value = copyAttributeValue(attribute, from: element, maxAttempts: maxAttempts),
              let number = value as? NSNumber else {
            return nil
        }
        return number.boolValue
    }

    static func cgWindowID(for element: AXUIElement) -> CGWindowID? {
        AXWindowIDBridge.cgWindowID(for: element)
    }

    func cgWindowID(for element: AXUIElement, maxAttempts: Int = 2) -> UInt32? {
        if let bridgedID = AXWindowIDBridge.cgWindowID(for: element) {
            return bridgedID
        }

        for attribute in AXWindowIDBridge.fallbackAttributeNames {
            if let id = numericWindowIDAttribute(attribute, from: element, maxAttempts: maxAttempts) {
                return id
            }
        }

        return nil
    }

    /// 校验一个**缓存下来的** AX 元素是否仍指向期望的窗口。三态，不折叠：
    /// - `true`：确认是同一个窗口，可以直接用。
    /// - `false`：读到了、但换了窗口（cgWindowID 复用）——缓存条目必须作废。
    /// - `nil`：**没读到**（App 打盹 / 超时）。这不是陈旧的证据，调用方只该回落到既有捕获链，
    ///   **不要因此删缓存**——把一次瞬时超时固化成永久失效，比原来的 bug 更糟
    ///   （同 `AppNameRegistry` 那条教训）。
    func matchesCGWindowID(
        _ expected: CGWindowID,
        element: AXUIElement,
        messagingTimeout: TimeInterval
    ) -> Bool? {
        applyMessagingTimeout(messagingTimeout, to: element)
        guard let actual = AXWindowIDBridge.cgWindowID(for: element) else { return nil }
        return actual == expected
    }

    func elementAttribute(
        _ attribute: CFString,
        from element: AXUIElement,
        maxAttempts: Int = 2
    ) -> AXUIElement? {
        guard let value = copyAttributeValue(attribute, from: element, maxAttempts: maxAttempts),
              CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    func frame(of element: AXUIElement, maxAttempts: Int = 2) -> CGRect? {
        guard let positionAX = copyAttributeValue(kAXPositionAttribute as CFString, from: element, maxAttempts: maxAttempts),
              let sizeAX = copyAttributeValue(kAXSizeAttribute as CFString, from: element, maxAttempts: maxAttempts) else {
            return nil
        }

        guard let position = axValue(from: positionAX),
              let sizeValueRef = axValue(from: sizeAX) else {
            return nil
        }

        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetType(position) == .cgPoint,
              AXValueGetType(sizeValueRef) == .cgSize,
              AXValueGetValue(position, .cgPoint, &point),
              AXValueGetValue(sizeValueRef, .cgSize, &size) else {
            return nil
        }

        return CGRect(origin: point, size: size)
    }

    func frame(of element: AXUIElement, messagingTimeout: TimeInterval) -> CGRect? {
        applyMessagingTimeout(messagingTimeout, to: element)
        return frame(of: element, maxAttempts: 1)
    }

    func frameSettableStatus(
        of element: AXUIElement,
        messagingTimeout: TimeInterval = 0.1
    ) -> AXWindowFrameSettableStatus {
        applyMessagingTimeout(messagingTimeout, to: element)
        return AXWindowFrameSettableStatus(
            position: settableStatus(kAXPositionAttribute as CFString, on: element),
            size: settableStatus(kAXSizeAttribute as CFString, on: element)
        )
    }

    func setSize(
        _ size: CGSize,
        for element: AXUIElement,
        messagingTimeout: TimeInterval = 0.1,
        verificationTolerance: CGFloat = 1,
        onlyIfCurrentMatches expectedCurrentFrame: CGRect? = nil,
        restoreOnFailureTo restoreFrame: CGRect? = nil
    ) -> AXWindowFrameWriteResult {
        applyMessagingTimeout(messagingTimeout, to: element)
        guard isValid(size: size), isValid(tolerance: verificationTolerance),
              expectedCurrentFrame.map(isValid(frame:)) ?? true,
              restoreFrame.map(isValid(frame:)) ?? true else {
            return .failure(reason: .invalidGeometry, rollback: .notRequested)
        }

        switch writeSize(
            size,
            to: element,
            verificationTolerance: verificationTolerance,
            onlyIfCurrentMatches: expectedCurrentFrame
        ) {
        case let .success(actualFrame):
            return .success(actualFrame: actualFrame)
        case let .failure(reason):
            return .failure(
                reason: reason,
                rollback: rollbackResult(
                    after: reason,
                    to: restoreFrame,
                    for: element,
                    verificationTolerance: verificationTolerance
                )
            )
        }
    }

    func setFrame(
        _ frame: CGRect,
        for element: AXUIElement,
        messagingTimeout: TimeInterval = 0.1,
        verificationTolerance: CGFloat = 1,
        onlyIfCurrentMatches expectedCurrentFrame: CGRect? = nil,
        restoreOnFailureTo restoreFrame: CGRect? = nil
    ) -> AXWindowFrameWriteResult {
        applyMessagingTimeout(messagingTimeout, to: element)
        guard isValid(frame: frame), isValid(tolerance: verificationTolerance),
              expectedCurrentFrame.map(isValid(frame:)) ?? true,
              restoreFrame.map(isValid(frame:)) ?? true else {
            return .failure(reason: .invalidGeometry, rollback: .notRequested)
        }

        switch writeFrame(
            frame,
            to: element,
            verificationTolerance: verificationTolerance,
            onlyIfCurrentMatches: expectedCurrentFrame
        ) {
        case let .success(actualFrame):
            return .success(actualFrame: actualFrame)
        case let .failure(reason):
            return .failure(
                reason: reason,
                rollback: rollbackResult(
                    after: reason,
                    to: restoreFrame,
                    for: element,
                    verificationTolerance: verificationTolerance
                )
            )
        }
    }

    func setMinimized(_ minimized: Bool, for handle: AXWindowHandle) -> Bool {
        let value: CFTypeRef = minimized ? kCFBooleanTrue : kCFBooleanFalse
        let result = AXUIElementSetAttributeValue(
            handle.element,
            kAXMinimizedAttribute as CFString,
            value
        )
        return result == .success
    }

    func copyAttributeValue(
        _ attribute: CFString,
        from element: AXUIElement,
        maxAttempts: Int = 2
    ) -> CFTypeRef? {
        var value: CFTypeRef?
        let result = copyAttributeValue(attribute, from: element, into: &value, maxAttempts: maxAttempts)
        return result == .success ? value : nil
    }

    @discardableResult
    func copyAttributeValue(
        _ attribute: CFString,
        from element: AXUIElement,
        into value: inout CFTypeRef?,
        maxAttempts: Int = 2
    ) -> AXError {
        var attempt = 0
        var lastResult: AXError = .failure
        while attempt < maxAttempts {
            let result = AXUIElementCopyAttributeValue(element, attribute, &value)
            if result == .success {
                return result
            }

            lastResult = result
            if result != .cannotComplete {
                return result
            }

            attempt += 1
        }

        return lastResult
    }

    private func numericWindowIDAttribute(
        _ attribute: CFString,
        from element: AXUIElement,
        maxAttempts: Int
    ) -> UInt32? {
        guard let value = copyAttributeValue(attribute, from: element, maxAttempts: maxAttempts) else {
            return nil
        }
        return AXWindowIDBridge.cgWindowID(from: value)
    }

    private func axValue(from value: CFTypeRef) -> AXValue? {
        guard CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        return unsafeBitCast(value, to: AXValue.self)
    }

    private func settableStatus(
        _ attribute: CFString,
        on element: AXUIElement
    ) -> AXWindowAttributeSettableStatus {
        var isSettable = DarwinBoolean(false)
        let result = AXUIElementIsAttributeSettable(element, attribute, &isSettable)
        guard result == .success else { return .unread(result) }
        return isSettable.boolValue ? .settable : .notSettable
    }

    private func writeSize(
        _ size: CGSize,
        to element: AXUIElement,
        verificationTolerance: CGFloat,
        onlyIfCurrentMatches expectedCurrentFrame: CGRect? = nil
    ) -> Result<CGRect, AXWindowFrameWriteFailure> {
        guard let initialFrame = frame(of: element, maxAttempts: 1) else {
            return .failure(.initialFrameUnavailable)
        }
        if let expectedCurrentFrame,
           !framesMatch(initialFrame, expectedCurrentFrame, tolerance: verificationTolerance) {
            return .failure(.initialFrameMismatch(expected: expectedCurrentFrame, actual: initialFrame))
        }

        let expectedFrame = CGRect(origin: initialFrame.origin, size: size)
        if framesMatch(initialFrame, expectedFrame, tolerance: verificationTolerance) {
            return .success(initialFrame)
        }

        switch settableStatus(kAXSizeAttribute as CFString, on: element) {
        case .settable:
            break
        case .notSettable:
            return .failure(.attributeNotSettable(.size))
        case let .unread(error):
            return .failure(.capabilityQueryFailed(attribute: .size, error: error))
        }

        var mutableSize = size
        guard let sizeValue = AXValueCreate(.cgSize, &mutableSize) else {
            return .failure(.valueCreationFailed(.size))
        }
        if let expectedCurrentFrame {
            guard let currentFrame = frame(of: element, maxAttempts: 1) else {
                return .failure(.initialFrameUnavailable)
            }
            guard framesMatch(currentFrame, expectedCurrentFrame, tolerance: verificationTolerance) else {
                return .failure(.initialFrameMismatch(expected: expectedCurrentFrame, actual: currentFrame))
            }
        }

        let writeResult = AXUIElementSetAttributeValue(
            element,
            kAXSizeAttribute as CFString,
            sizeValue
        )
        guard writeResult == .success else {
            return .failure(.writeFailed(attribute: .size, error: writeResult))
        }

        guard let actualFrame = frame(of: element, maxAttempts: 1) else {
            return .failure(.verificationUnavailable)
        }
        guard framesMatch(actualFrame, expectedFrame, tolerance: verificationTolerance) else {
            return .failure(.verificationMismatch(expected: expectedFrame, actual: actualFrame))
        }
        return .success(actualFrame)
    }

    private func writeFrame(
        _ targetFrame: CGRect,
        to element: AXUIElement,
        verificationTolerance: CGFloat,
        onlyIfCurrentMatches expectedCurrentFrame: CGRect? = nil
    ) -> Result<CGRect, AXWindowFrameWriteFailure> {
        guard let initialFrame = frame(of: element, maxAttempts: 1) else {
            return .failure(.initialFrameUnavailable)
        }
        if let expectedCurrentFrame,
           !framesMatch(initialFrame, expectedCurrentFrame, tolerance: verificationTolerance) {
            return .failure(.initialFrameMismatch(expected: expectedCurrentFrame, actual: initialFrame))
        }
        if framesMatch(initialFrame, targetFrame, tolerance: verificationTolerance) {
            return .success(initialFrame)
        }

        let needsSize = !sizesMatch(
            initialFrame.size,
            targetFrame.size,
            tolerance: verificationTolerance
        )
        let needsPosition = !pointsMatch(
            initialFrame.origin,
            targetFrame.origin,
            tolerance: verificationTolerance
        )

        if needsSize {
            switch settableStatus(kAXSizeAttribute as CFString, on: element) {
            case .settable:
                break
            case .notSettable:
                return .failure(.attributeNotSettable(.size))
            case let .unread(error):
                return .failure(.capabilityQueryFailed(attribute: .size, error: error))
            }
        }
        if needsPosition {
            switch settableStatus(kAXPositionAttribute as CFString, on: element) {
            case .settable:
                break
            case .notSettable:
                return .failure(.attributeNotSettable(.position))
            case let .unread(error):
                return .failure(.capabilityQueryFailed(attribute: .position, error: error))
            }
        }

        var mutableSize = targetFrame.size
        let sizeValue = needsSize ? AXValueCreate(.cgSize, &mutableSize) : nil
        if needsSize, sizeValue == nil {
            return .failure(.valueCreationFailed(.size))
        }

        var mutablePosition = targetFrame.origin
        let positionValue = needsPosition ? AXValueCreate(.cgPoint, &mutablePosition) : nil
        if needsPosition, positionValue == nil {
            return .failure(.valueCreationFailed(.position))
        }
        if let expectedCurrentFrame {
            guard let currentFrame = frame(of: element, maxAttempts: 1) else {
                return .failure(.initialFrameUnavailable)
            }
            guard framesMatch(currentFrame, expectedCurrentFrame, tolerance: verificationTolerance) else {
                return .failure(.initialFrameMismatch(expected: expectedCurrentFrame, actual: currentFrame))
            }
        }

        if let sizeValue {
            let result = AXUIElementSetAttributeValue(
                element,
                kAXSizeAttribute as CFString,
                sizeValue
            )
            guard result == .success else {
                return .failure(.writeFailed(attribute: .size, error: result))
            }
        }

        if let positionValue {
            let result = AXUIElementSetAttributeValue(
                element,
                kAXPositionAttribute as CFString,
                positionValue
            )
            guard result == .success else {
                return .failure(.writeFailed(attribute: .position, error: result))
            }
        }

        guard let actualFrame = frame(of: element, maxAttempts: 1) else {
            return .failure(.verificationUnavailable)
        }
        guard framesMatch(actualFrame, targetFrame, tolerance: verificationTolerance) else {
            return .failure(.verificationMismatch(expected: targetFrame, actual: actualFrame))
        }
        return .success(actualFrame)
    }

    private func rollbackResult(
        after failure: AXWindowFrameWriteFailure,
        to restoreFrame: CGRect?,
        for element: AXUIElement,
        verificationTolerance: CGFloat
    ) -> AXWindowFrameRollbackResult {
        guard failure.mayHaveMutatedWindow, let restoreFrame else {
            return .notRequested
        }

        switch writeFrame(
            restoreFrame,
            to: element,
            verificationTolerance: verificationTolerance
        ) {
        case let .success(actualFrame):
            return .restored(actualFrame: actualFrame)
        case let .failure(reason):
            return .failed(
                reason: reason,
                actualFrame: frame(of: element, maxAttempts: 1)
            )
        }
    }

    private func isValid(size: CGSize) -> Bool {
        size.width.isFinite && size.height.isFinite && size.width > 0 && size.height > 0
    }

    private func isValid(frame: CGRect) -> Bool {
        frame.origin.x.isFinite
            && frame.origin.y.isFinite
            && isValid(size: frame.size)
    }

    private func isValid(tolerance: CGFloat) -> Bool {
        tolerance.isFinite && tolerance >= 0
    }

    private func framesMatch(_ lhs: CGRect, _ rhs: CGRect, tolerance: CGFloat) -> Bool {
        pointsMatch(lhs.origin, rhs.origin, tolerance: tolerance)
            && sizesMatch(lhs.size, rhs.size, tolerance: tolerance)
    }

    private func pointsMatch(_ lhs: CGPoint, _ rhs: CGPoint, tolerance: CGFloat) -> Bool {
        abs(lhs.x - rhs.x) <= tolerance && abs(lhs.y - rhs.y) <= tolerance
    }

    private func sizesMatch(_ lhs: CGSize, _ rhs: CGSize, tolerance: CGFloat) -> Bool {
        abs(lhs.width - rhs.width) <= tolerance && abs(lhs.height - rhs.height) <= tolerance
    }

    private func applyMessagingTimeout(_ timeout: TimeInterval?, to element: AXUIElement) {
        guard let timeout else { return }
        _ = AXUIElementSetMessagingTimeout(element, Float(timeout))
    }

    private func bestMatch(
        for target: AXWindowTarget,
        from snapshots: [AXWindowSnapshot]
    ) -> AXWindowSnapshot? {
        let candidates = snapshots.map {
            AXWindowMatchPolicy.Candidate(title: $0.title, bounds: $0.bounds)
        }
        guard let index = AXWindowMatchPolicy.uniqueBestMatchIndex(
            targetTitle: target.title,
            targetBounds: target.bounds,
            candidates: candidates
        ) else { return nil }
        return snapshots[index]
    }

}

private enum AXWindowIDBridge {
    typealias GetWindowFunction = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError

    static let fallbackAttributeNames: [CFString] = [
        "AXWindowID" as CFString,
        "AXWindowNumber" as CFString
    ]

    private static let getWindowFunction: GetWindowFunction? = {
        let frameworkPaths = [
            "/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices",
            "/System/Library/Frameworks/ApplicationServices.framework/Frameworks/HIServices.framework/HIServices"
        ]
        let symbolNames = [
            "_AXUIElementGetWindow",
            "AXUIElementGetWindow"
        ]

        for path in frameworkPaths {
            guard let handle = dlopen(path, RTLD_LAZY) else { continue }
            for symbolName in symbolNames {
                if let symbol = dlsym(handle, symbolName) {
                    return unsafeBitCast(symbol, to: GetWindowFunction.self)
                }
            }
        }

        return nil
    }()

    static func cgWindowID(for element: AXUIElement) -> UInt32? {
        guard let getWindowFunction else { return nil }

        var windowID = CGWindowID(0)
        guard getWindowFunction(element, &windowID) == .success else {
            return nil
        }
        return windowID == 0 ? nil : UInt32(windowID)
    }

    static func cgWindowID(from value: CFTypeRef) -> UInt32? {
        if let number = value as? NSNumber {
            let id = number.uint32Value
            return id == 0 ? nil : id
        }

        if let string = value as? String,
           let id = UInt32(string.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return id == 0 ? nil : id
        }

        return nil
    }
}

// MARK: - Mission Control (MC-2: AX actions and the Dock's overview probe)

/// The five actions the Mission Control overlay performs. Close, minimize and zoom press the window's
/// own AX buttons, so the app runs its own animation, save sheet and close veto; hide and quit go
/// through `NSRunningApplication` rather than forging a menu click. Nothing here posts events.
enum WindowActionExecutor {
    enum Outcome: Equatable {
        case performed
        case unsupported
        case failed(AXError)
    }

    /// Acts on the app window the frame describes. Titles are matched first and the app's frontmost
    /// window is the fallback, so a retitled document still closes rather than doing nothing.
    static func perform(_ action: MissionControlWindowAction, on frame: MissionControlWindowFrame) -> Outcome {
        guard let target = locate(frame) else { return .unsupported }
        switch action {
        case .close:
            return press(kAXCloseButtonAttribute, of: target.element)
        case .minimize:
            return press(kAXMinimizeButtonAttribute, of: target.element)
        case .zoom:
            return press(kAXZoomButtonAttribute, of: target.element)
        case .hide:
            guard let app = NSRunningApplication(processIdentifier: target.pid) else { return .unsupported }
            return app.hide() ? .performed : .failed(.cannotComplete)
        case .quit:
            guard let app = NSRunningApplication(processIdentifier: target.pid) else { return .unsupported }
            return app.terminate() ? .performed : .failed(.cannotComplete)
        }
    }

    /// The app's real AX window. A 0.4 s messaging timeout keeps one hung app from stalling the
    /// overlay; a window that cannot be read is reported unsupported, never guessed at.
    static func locate(_ frame: MissionControlWindowFrame) -> (element: AXUIElement, pid: Int32)? {
        let candidates = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular
                && ($0.localizedName == frame.appName
                    || (frame.bundleID != nil && $0.bundleIdentifier == frame.bundleID))
        }
        let reader = AXWindowReader()
        for app in candidates {
            let windows = reader.inventoryWindows(forPID: app.processIdentifier, messagingTimeout: 0.4).windowsOrEmpty
            let wanted = frame.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let match = wanted.isEmpty
                ? windows.first
                : windows.first { ($0.title ?? "").caseInsensitiveCompare(wanted) == .orderedSame } ?? windows.first
            if let match { return (match.element, app.processIdentifier) }
        }
        return nil
    }

    private static func press(_ attribute: String, of element: AXUIElement) -> Outcome {
        var raw: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &raw)
        guard result == .success, let raw, CFGetTypeID(raw) == AXUIElementGetTypeID() else {
            return result == .success ? .unsupported : .failed(result)
        }
        let button = raw as! AXUIElement
        let press = AXUIElementPerformAction(button, kAXPressAction as CFString)
        return press == .success ? .performed : .failed(press)
    }
}

/// Reads the Dock's Mission Control surface: one window covering most of a display, with thumbnail
/// children. macOS has no public Mission Control API, so this is deliberately geometry-driven and
/// best-effort — an empty result means "unavailable on this macOS", never a fabricated layout.
enum MissionControlDockProbe {
    struct Probe: Equatable {
        let isActive: Bool
        let frames: [MissionControlWindowFrame]
        /// The Dock answered Accessibility reads at all. False means this macOS exposes nothing to
        /// observe, which the settings page reports as "unavailable", never as "off".
        let dockReadable: Bool
    }

    static func probe() -> Probe {
        guard let dock = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == "com.apple.dock"
        }) else { return Probe(isActive: false, frames: [], dockReadable: false) }

        let reader = AXWindowReader()
        let snapshots = reader.windows(forPID: dock.processIdentifier)
        let readable = !snapshots.isEmpty
        let overview = snapshots.first { snapshot in
            guard let bounds = snapshot.bounds, bounds.width > 200, bounds.height > 200 else { return false }
            return NSScreen.screens.contains { coverage(of: bounds, in: $0.frame) > 0.5 }
        }
        guard let overview, let overviewBounds = overview.bounds else {
            return Probe(isActive: false, frames: [], dockReadable: readable)
        }
        let thumbs = thumbnails(in: overview.element, within: overviewBounds)
        return Probe(isActive: true, frames: thumbs, dockReadable: true)
    }

    /// Thumbnails are one or two AX levels below the overview window. A candidate is a rect at least
    /// 80×50 inside the overview and no wider than 80 % of it (the backdrop itself is excluded).
    private static func thumbnails(in element: AXUIElement, within bounds: CGRect, depth: Int = 0) -> [MissionControlWindowFrame] {
        guard depth < 3 else { return [] }
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &raw) == .success,
              let children = raw as? [AXUIElement] else { return [] }

        var frames: [MissionControlWindowFrame] = []
        for child in children {
            guard let rect = frame(of: child), rect.width >= 80, rect.height >= 50,
                  bounds.contains(rect.insetBy(dx: 4, dy: 4)),
                  rect.width <= bounds.width * 0.8, rect.height <= bounds.height * 0.8 else {
                frames.append(contentsOf: thumbnails(in: child, within: bounds, depth: depth + 1))
                continue
            }
            let title = stringAttribute(kAXTitleAttribute as CFString, of: child)
            let description = stringAttribute(kAXDescriptionAttribute as CFString, of: child)
            let app = stringAttribute(kAXSubroleAttribute as CFString, of: child)
            frames.append(
                MissionControlWindowFrame(
                    id: UInt32(frames.count + 1 + depth * 100),
                    bundleID: nil,
                    appName: description ?? app ?? "Window",
                    title: title,
                    frame: rect,
                    state: .standard,
                    isFocused: false
                )
            )
        }
        return frames
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        var positionRaw: CFTypeRef?
        var sizeRaw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionRaw) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRaw) == .success,
              let positionRaw, let sizeRaw,
              CFGetTypeID(positionRaw) == AXValueGetTypeID(),
              CFGetTypeID(sizeRaw) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionRaw as! AXValue, .cgPoint, &point),
              AXValueGetValue(sizeRaw as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: point, size: size)
    }

    private static func stringAttribute(_ attribute: CFString, of element: AXUIElement) -> String? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &raw) == .success,
              let text = raw as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// The share of `screen` a window covers. Mission Control's backdrop spans the whole display; an
    /// ordinary Dock window (the Dock strip) is a fraction of its height.
    static func coverage(of rect: CGRect, in screen: CGRect) -> Double {
        let overlap = rect.intersection(screen)
        guard !overlap.isNull, screen.width > 0, screen.height > 0 else { return 0 }
        return Double((overlap.width * overlap.height) / (screen.width * screen.height))
    }
}
