import AppKit

/// Reads raw trackpad contact frames from the private MultitouchSupport framework to spot a four-finger-or-more
/// pinch (macOS sends that gesture only to the system, never to apps). Soft-fails: if the framework or a symbol
/// is missing after a macOS update, `start()` returns false and nothing else is affected. Needs no permission.
/// Created and started only while the Settings toggle is on.
final class MultitouchPinchMonitor {
    private typealias Frames = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int32, Double, Int32) -> Int32
    private typealias CreateList = @convention(c) () -> Unmanaged<CFArray>
    private typealias Register = @convention(c) (UnsafeMutableRawPointer, Frames) -> Void
    private typealias Start = @convention(c) (UnsafeMutableRawPointer, Int32) -> Void
    private typealias Stop = @convention(c) (UnsafeMutableRawPointer) -> Void

    /// Called on the main queue when a pinch-in is recognised.
    var onPinch: (() -> Void)?

    fileprivate static weak var active: MultitouchPinchMonitor?
    fileprivate let lock = NSLock()
    fileprivate var detector = PinchDetector()
    private var devices: [AnyObject] = []
    private var stopFn: Stop?
    private var unregisterFn: Register?

    /// Touch record layout up to the normalised position (stable for years across macOS releases).
    private struct Touch {
        var frame: Int32; var timestamp: Double; var path: Int32; var state: Int32; var finger: Int32; var hand: Int32
        var x: Float; var y: Float; var vx: Float; var vy: Float
    }

    @discardableResult
    func start() -> Bool {
        guard devices.isEmpty,
              let h = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW),
              let create = dlsym(h, "MTDeviceCreateList"), let reg = dlsym(h, "MTRegisterContactFrameCallback"),
              let startSym = dlsym(h, "MTDeviceStart"), let stopSym = dlsym(h, "MTDeviceStop"),
              let unreg = dlsym(h, "MTUnregisterContactFrameCallback") else { return false }
        let list = unsafeBitCast(create, to: CreateList.self)().takeRetainedValue() as [AnyObject]
        guard !list.isEmpty else { return false }
        stopFn = unsafeBitCast(stopSym, to: Stop.self)
        unregisterFn = unsafeBitCast(unreg, to: Register.self)
        Self.active = self
        let callback: Frames = { _, raw, count, _, _ in
            guard let raw, let monitor = MultitouchPinchMonitor.active else { return 0 }
            let touches = raw.assumingMemoryBound(to: Touch.self)
            let points = (0..<Int(count)).map { (x: Double(touches[$0].x), y: Double(touches[$0].y)) }
            monitor.lock.lock()
            let fired = monitor.detector.feed(fingers: points.count, spread: PinchDetector.spread(of: points))
            monitor.lock.unlock()
            if fired { DispatchQueue.main.async { monitor.onPinch?() } }
            return 0
        }
        for device in list {
            let p = Unmanaged.passUnretained(device).toOpaque()
            unsafeBitCast(reg, to: Register.self)(p, callback)
            unsafeBitCast(startSym, to: Start.self)(p, 0)
        }
        devices = list
        return true
    }

    func stop() {
        guard !devices.isEmpty else { return }
        for device in devices {
            let p = Unmanaged.passUnretained(device).toOpaque()
            stopFn?(p)
        }
        devices = []
        if Self.active === self { Self.active = nil }
    }

    deinit { stop() }
}
