import CoreGraphics
import Foundation

enum DesktopBoxMaterialStyle: String, Codable, CaseIterable, Sendable {
    case inheritDock
    case frostedGlass
    case tintedGlass
    case solidCard
    case clearMinimal
}

enum DesktopBoxBorderStyle: String, Codable, CaseIterable, Sendable {
    case standard
    case glow
    case hairline
    case none
}

enum DesktopBoxTextTreatment: String, Codable, CaseIterable, Sendable {
    case auto
    case shadowed
    case highContrast
    case monospaced
}

enum DesktopPanoramaScaleMode: String, Codable, CaseIterable, Sendable {
    case aspectFill
    case aspectFit
}

/// Pure hex color parser/normalizer supporting `#RGB`, `#RRGGBB`, or bare hex strings.
enum DesktopHexColor {
    static func parse(_ raw: String) -> (r: Double, g: Double, b: Double)? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let stripped = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        let expanded: String
        switch stripped.count {
        case 3:
            expanded = stripped.map { "\($0)\($0)" }.joined()
        case 6:
            expanded = stripped
        default:
            return nil
        }
        guard let value = UInt32(expanded, radix: 16), expanded.count == 6 else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        return (r, g, b)
    }

    static func normalized(_ raw: String) -> String? {
        guard let rgb = parse(raw) else { return nil }
        return String(
            format: "#%02X%02X%02X",
            Int((rgb.r * 255.0).rounded()),
            Int((rgb.g * 255.0).rounded()),
            Int((rgb.b * 255.0).rounded())
        )
    }
}

enum DesktopWidgetIconBadge: Codable, Equatable, Sendable {
    case systemDefault
    case emoji(String)
    case sfSymbol(String)
    case customImage(String)

    private enum CodingKeys: String, CodingKey { case type, value }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decodeIfPresent(String.self, forKey: .type) ?? "systemDefault"
        let value = try c.decodeIfPresent(String.self, forKey: .value) ?? ""
        switch type {
        case "emoji":
            let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if let first = cleaned.first {
                self = .emoji(String(first))
            } else {
                self = .systemDefault
            }
        case "sfSymbol":
            self = value.isEmpty ? .systemDefault : .sfSymbol(value)
        case "customImage":
            self = value.isEmpty ? .systemDefault : .customImage(value)
        default:
            self = .systemDefault
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .systemDefault:
            try c.encode("systemDefault", forKey: .type)
        case .emoji(let ch):
            let cleaned = ch.trimmingCharacters(in: .whitespacesAndNewlines)
            try c.encode("emoji", forKey: .type)
            try c.encode(cleaned.first.map(String.init) ?? "", forKey: .value)
        case .sfSymbol(let name):
            try c.encode("sfSymbol", forKey: .type)
            try c.encode(name, forKey: .value)
        case .customImage(let path):
            try c.encode("customImage", forKey: .type)
            try c.encode(path, forKey: .value)
        }
    }
}

enum DesktopBoxBackground: Codable, Equatable, Sendable {
    case materialOnly
    case tint(hex: String, opacity: Double)
    case image(path: String, opacity: Double, blurRadius: Double)
    case panorama

    private enum CodingKeys: String, CodingKey { case type, hex, path, opacity, blurRadius }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decodeIfPresent(String.self, forKey: .type) ?? "materialOnly"
        switch type {
        case "tint":
            let rawHex = try c.decodeIfPresent(String.self, forKey: .hex) ?? "#3B82F6"
            let hex = DesktopHexColor.normalized(rawHex) ?? "#3B82F6"
            let opacity = Self.clampedOpacity(try c.decodeIfPresent(Double.self, forKey: .opacity) ?? 0.25)
            self = .tint(hex: hex, opacity: opacity)
        case "image":
            let path = try c.decodeIfPresent(String.self, forKey: .path) ?? ""
            let opacity = Self.clampedOpacity(try c.decodeIfPresent(Double.self, forKey: .opacity) ?? 0.7)
            let blur = Self.clampedBlur(try c.decodeIfPresent(Double.self, forKey: .blurRadius) ?? 0)
            self = path.isEmpty ? .materialOnly : .image(path: path, opacity: opacity, blurRadius: blur)
        case "panorama":
            self = .panorama
        default:
            self = .materialOnly
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .materialOnly:
            try c.encode("materialOnly", forKey: .type)
        case .tint(let hex, let opacity):
            try c.encode("tint", forKey: .type)
            try c.encode(DesktopHexColor.normalized(hex) ?? "#3B82F6", forKey: .hex)
            try c.encode(Self.clampedOpacity(opacity), forKey: .opacity)
        case .image(let path, let opacity, let blurRadius):
            try c.encode("image", forKey: .type)
            try c.encode(path, forKey: .path)
            try c.encode(Self.clampedOpacity(opacity), forKey: .opacity)
            try c.encode(Self.clampedBlur(blurRadius), forKey: .blurRadius)
        case .panorama:
            try c.encode("panorama", forKey: .type)
        }
    }

    static func clampedOpacity(_ value: Double) -> Double {
        min(max(value, 0.05), 1.0)
    }

    static func clampedBlur(_ value: Double) -> Double {
        min(max(value, 0.0), 24.0)
    }
}

struct DesktopWidgetAppearance: Codable, Equatable, Sendable {
    var materialOverride: DesktopBoxMaterialStyle?
    var borderStyle: DesktopBoxBorderStyle
    var accentHex: String?
    var textTreatment: DesktopBoxTextTreatment
    var iconBadge: DesktopWidgetIconBadge
    var background: DesktopBoxBackground
    var cornerRadiusOverride: CGFloat?

    static let standard = DesktopWidgetAppearance()

    init(
        materialOverride: DesktopBoxMaterialStyle? = nil,
        borderStyle: DesktopBoxBorderStyle = .standard,
        accentHex: String? = nil,
        textTreatment: DesktopBoxTextTreatment = .auto,
        iconBadge: DesktopWidgetIconBadge = .systemDefault,
        background: DesktopBoxBackground = .materialOnly,
        cornerRadiusOverride: CGFloat? = nil
    ) {
        self.materialOverride = materialOverride
        self.borderStyle = borderStyle
        self.accentHex = accentHex.flatMap(DesktopHexColor.normalized)
        self.textTreatment = textTreatment
        if case .emoji(let raw) = iconBadge {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            self.iconBadge = trimmed.first.map { .emoji(String($0)) } ?? .systemDefault
        } else {
            self.iconBadge = iconBadge
        }
        switch background {
        case .tint(let hex, let opacity):
            self.background = .tint(
                hex: DesktopHexColor.normalized(hex) ?? "#3B82F6",
                opacity: DesktopBoxBackground.clampedOpacity(opacity)
            )
        case .image(let path, let opacity, let blurRadius):
            self.background = .image(
                path: path,
                opacity: DesktopBoxBackground.clampedOpacity(opacity),
                blurRadius: DesktopBoxBackground.clampedBlur(blurRadius)
            )
        default:
            self.background = background
        }
        self.cornerRadiusOverride = cornerRadiusOverride.map {
            min(max($0, DesktopCanvasConfig.cornerRadiusRange.lowerBound), DesktopCanvasConfig.cornerRadiusRange.upperBound)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case materialOverride, borderStyle, accentHex, textTreatment, iconBadge, background, cornerRadiusOverride
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            materialOverride: try c.decodeIfPresent(DesktopBoxMaterialStyle.self, forKey: .materialOverride),
            borderStyle: try c.decodeIfPresent(DesktopBoxBorderStyle.self, forKey: .borderStyle) ?? .standard,
            accentHex: try c.decodeIfPresent(String.self, forKey: .accentHex),
            textTreatment: try c.decodeIfPresent(DesktopBoxTextTreatment.self, forKey: .textTreatment) ?? .auto,
            iconBadge: try c.decodeIfPresent(DesktopWidgetIconBadge.self, forKey: .iconBadge) ?? .systemDefault,
            background: try c.decodeIfPresent(DesktopBoxBackground.self, forKey: .background) ?? .materialOnly,
            cornerRadiusOverride: try c.decodeIfPresent(CGFloat.self, forKey: .cornerRadiusOverride)
        )
    }
}

struct DesktopCanvasThemeState: Equatable, Sendable {
    var materialStyle: DesktopBoxMaterialStyle = .inheritDock
    var panoramaEnabled: Bool = false
    var panoramaImagePath: String?
    var panoramaOpacity: Double = DesktopCanvasConfig.defaultPanoramaOpacity
    var panoramaBlur: Double = DesktopCanvasConfig.defaultPanoramaBlur
    var panoramaScaleMode: DesktopPanoramaScaleMode = .aspectFill

    nonisolated static func load(defaults: UserDefaults = .standard) -> DesktopCanvasThemeState {
        let rawMaterial = defaults.string(forKey: DesktopCanvasConfig.materialStyleKey) ?? ""
        let rawScale = defaults.string(forKey: DesktopCanvasConfig.panoramaScaleModeKey) ?? ""
        let opacity = defaults.object(forKey: DesktopCanvasConfig.panoramaOpacityKey) as? Double
            ?? DesktopCanvasConfig.defaultPanoramaOpacity
        let blur = defaults.object(forKey: DesktopCanvasConfig.panoramaBlurKey) as? Double
            ?? DesktopCanvasConfig.defaultPanoramaBlur
        return DesktopCanvasThemeState(
            materialStyle: DesktopBoxMaterialStyle(rawValue: rawMaterial) ?? .inheritDock,
            panoramaEnabled: defaults.bool(forKey: DesktopCanvasConfig.panoramaEnabledKey),
            panoramaImagePath: defaults.string(forKey: DesktopCanvasConfig.panoramaImagePathKey),
            panoramaOpacity: DesktopBoxBackground.clampedOpacity(opacity),
            panoramaBlur: DesktopBoxBackground.clampedBlur(blur),
            panoramaScaleMode: DesktopPanoramaScaleMode(rawValue: rawScale) ?? .aspectFill
        )
    }
}
