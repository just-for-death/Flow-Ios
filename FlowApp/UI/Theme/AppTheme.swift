import SwiftUI
import Observation

// MARK: - ThemeMode (29 values — matches Android Theme.kt)
enum ThemeMode: String, CaseIterable, Identifiable, Codable {
    case system        = "SYSTEM"
    case light         = "LIGHT"
    case dark          = "DARK"
    case oled          = "OLED"
    case lavenderMist  = "LAVENDER_MIST"
    case oceanBlue     = "OCEAN_BLUE"
    case forestGreen   = "FOREST_GREEN"
    case sunsetOrange  = "SUNSET_ORANGE"
    case purpleNebula  = "PURPLE_NEBULA"
    case midnightBlack = "MIDNIGHT_BLACK"
    case roseGold      = "ROSE_GOLD"
    case arcticIce     = "ARCTIC_ICE"
    case crimsonRed    = "CRIMSON_RED"
    case mintyFresh    = "MINTY_FRESH"
    case cosmicVoid    = "COSMIC_VOID"
    case solarFlare    = "SOLAR_FLARE"
    case cyberpunk     = "CYBERPUNK"
    case royalGold     = "ROYAL_GOLD"
    case nordicHorizon = "NORDIC_HORIZON"
    case espresso      = "ESPRESSO"
    case gunmetal      = "GUNMETAL"
    case mintLight     = "MINT_LIGHT"
    case roseLight     = "ROSE_LIGHT"
    case skyLight      = "SKY_LIGHT"
    case creamLight    = "CREAM_LIGHT"
    case monochrome    = "MONOCHROME"
    case custom        = "CUSTOM"
    case materialYou   = "MATERIAL_YOU"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system:        return "System"
        case .light:         return "Pure Light"
        case .dark:          return "Classic Dark"
        case .oled:          return "True Black (OLED)"
        case .lavenderMist:  return "Lavender Mist"
        case .oceanBlue:     return "Ocean Blue"
        case .forestGreen:   return "Forest Green"
        case .sunsetOrange:  return "Sunset Orange"
        case .purpleNebula:  return "Purple Nebula"
        case .midnightBlack: return "Midnight Black"
        case .roseGold:      return "Rose Gold"
        case .arcticIce:     return "Arctic Ice"
        case .crimsonRed:    return "Crimson Red"
        case .mintyFresh:    return "Minty Fresh"
        case .cosmicVoid:    return "Cosmic Void"
        case .solarFlare:    return "Solar Flare"
        case .cyberpunk:     return "Cyberpunk"
        case .royalGold:     return "Royal Gold"
        case .nordicHorizon: return "Nordic Horizon"
        case .espresso:      return "Espresso"
        case .gunmetal:      return "Gunmetal"
        case .mintLight:     return "Mint Light"
        case .roseLight:     return "Rose Light"
        case .skyLight:      return "Sky Light"
        case .creamLight:    return "Cream Light"
        case .monochrome:    return "Monochrome"
        case .custom:        return "Custom"
        case .materialYou:   return "Material You"
        }
    }

    var category: ThemeCategory {
        switch self {
        case .light, .mintLight, .roseLight, .skyLight, .creamLight: return .light
        case .custom: return .custom
        default: return .dark
        }
    }

    var isDark: Bool { category != .light }
}

enum ThemeCategory: String, CaseIterable, Identifiable {
    case light, dark, custom
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

// MARK: - CustomThemeColors (16 roles — matches Android)
struct CustomThemeColors: Codable, Equatable {
    var primary: UInt32 = 0xFF82B1FF
    var onPrimary: UInt32 = 0xFF000000
    var secondary: UInt32 = 0xFFFF4081
    var onSecondary: UInt32 = 0xFFFFFFFF
    var background: UInt32 = 0xFF121212
    var onBackground: UInt32 = 0xFFFFFFFF
    var surface: UInt32 = 0xFF1E1E1E
    var onSurface: UInt32 = 0xFFFFFFFF
    var surfaceVariant: UInt32 = 0xFF2C2C2C
    var onSurfaceVariant: UInt32 = 0xFFB0B0B0
    var error: UInt32 = 0xFFCF6679
    var onError: UInt32 = 0xFF000000
    var outline: UInt32 = 0xFF444444
    var scrim: UInt32 = 0xFF000000

    static func fromDefaults() -> CustomThemeColors {
        guard let raw = UserDefaults.standard.string(forKey: "custom_theme_colors") else {
            return CustomThemeColors()
        }
        let parts = raw.split(separator: ",").compactMap { UInt32($0) }
        guard parts.count >= 14 else { return CustomThemeColors() }
        var c = CustomThemeColors()
        c.primary = parts[0]; c.onPrimary = parts[1]
        c.secondary = parts[2]; c.onSecondary = parts[3]
        c.background = parts[4]; c.onBackground = parts[5]
        c.surface = parts[6]; c.onSurface = parts[7]
        c.surfaceVariant = parts[8]; c.onSurfaceVariant = parts[9]
        c.error = parts[10]; c.onError = parts[11]
        c.outline = parts[12]; c.scrim = parts[13]
        return c
    }

    func save() {
        let raw = [primary, onPrimary, secondary, onSecondary, background, onBackground,
                   surface, onSurface, surfaceVariant, onSurfaceVariant, error, onError, outline, scrim]
            .map(String.init).joined(separator: ",")
        UserDefaults.standard.set(raw, forKey: "custom_theme_colors")
    }
}

// MARK: - FlowThemePalette
struct FlowThemePalette {
    let primary, primaryContainer, onPrimary: Color
    let surface, surfaceVariant, onSurface, onSurfaceVariant: Color
    let background, error, errorContainer, outline, outlineVariant, sponsorBlock: Color

    static func palette(for mode: ThemeMode, custom: CustomThemeColors = .fromDefaults()) -> FlowThemePalette {
        switch mode {
        case .light:
            return p("#FF0000", "#FFEBEE", "#FFFFFF", "#F9F9F9", "#EEEEEE", "#0F0F0F", "#606060", "#FFFFFF", "#F44336", "#FFEBEE", "#E0E0E0", "#F0F0F0", "#4CAF50")
        case .dark:
            return p("#FF0000", "#3E1B23", "#FFFFFF", "#161616", "#282828", "#FFFFFF", "#AAAAAA", "#0F0F0F", "#CF6679", "#3E1B23", "#3A3A3A", "#2A2A2A", "#00D37A")
        case .oled:
            return p("#FF0000", "#1A1A1A", "#FFFFFF", "#121212", "#1A1A1A", "#FFFFFF", "#AAAAAA", "#000000", "#CF6679", "#3E1B23", "#2A2A2A", "#111111", "#00D37A")
        case .midnightBlack:
            return p("#00BCD4", "#1A2830", "#000000", "#0A0A0A", "#121212", "#FFFFFF", "#B0BEC5", "#000000", "#FF5252", "#3E1B23", "#1A1A1A", "#111111", "#00E676")
        case .lavenderMist:
            return t("#B39DDB", "#120F1A", "#1F1A2E", "#EDE7F6", "#9575CD", "#2A2235")
        case .oceanBlue:
            return t("#006994", "#0A1929", "#1A2332", "#E3F2FD", "#4FC3F7", "#2A3F5F")
        case .forestGreen:
            return t("#2E7D32", "#0D1F12", "#1B2D1F", "#E8F5E9", "#66BB6A", "#2F4C33")
        case .sunsetOrange:
            return t("#FF6F00", "#1F0F08", "#2D1810", "#FFECB3", "#FFAB40", "#4A2C1A")
        case .purpleNebula:
            return t("#7B1FA2", "#1A0C26", "#2A1A3D", "#F3E5F5", "#BA68C8", "#3D2957")
        case .roseGold:
            return t("#E91E63", "#1A0D12", "#2D1821", "#FCE4EC", "#FF6090", "#4A2535")
        case .arcticIce:
            return t("#00BCD4", "#0E1821", "#1A2830", "#E0F7FA", "#80DEEA", "#2A3F4A")
        case .crimsonRed:
            return t("#DC143C", "#1A0A0A", "#2D1414", "#FFEBEE", "#FF4757", "#4A1F1F")
        case .mintyFresh:
            return t("#80CBC4", "#0F1A18", "#1A2E2B", "#E0F2F1", "#4DB6AC", "#1E302D")
        case .cosmicVoid:
            return t("#7C4DFF", "#050505", "#121212", "#E0E0E0", "#651FFF", "#1A1225")
        case .solarFlare:
            return t("#FFD740", "#1A1500", "#2E2600", "#FFFDE7", "#FFAB00", "#352A10")
        case .cyberpunk:
            return t("#FF00FF", "#0D001A", "#1F0033", "#E0E0E0", "#00FFFF", "#200F35")
        case .royalGold:
            return t("#FFD700", "#050505", "#141414", "#FFF8E1", "#C5A000", "#333333")
        case .nordicHorizon:
            return t("#88C0D0", "#242933", "#2E3440", "#ECEFF4", "#81A1C1", "#434C5E")
        case .espresso:
            return t("#D7CCC8", "#181210", "#241A17", "#EFEBE9", "#A1887F", "#3E2723")
        case .gunmetal:
            return t("#78909C", "#0F1216", "#1A1F26", "#ECEFF1", "#546E7A", "#263238")
        case .mintLight:
            return p("#00BFA5", "#E0F2F1", "#FFFFFF", "#F1F8F7", "#E0F2F1", "#00332E", "#455A64", "#FFFFFF", "#F44336", "#FFEBEE", "#E0F2F1", "#F0F0F0", "#4CAF50")
        case .roseLight:
            return p("#EC407A", "#F8BBD0", "#FFFFFF", "#FCE4EC", "#F8BBD0", "#4A0E1C", "#880E4F", "#FFF8F9", "#F44336", "#FFEBEE", "#F8BBD0", "#FCE4EC", "#E91E63")
        case .skyLight:
            return p("#0288D1", "#B3E5FC", "#FFFFFF", "#E1F5FE", "#B3E5FC", "#013354", "#0277BD", "#F9FCFF", "#F44336", "#FFEBEE", "#B3E5FC", "#E1F5FE", "#03A9F4")
        case .creamLight:
            return p("#8D6E63", "#D7CCC8", "#FFFFFF", "#F5F5DC", "#D7CCC8", "#3E2723", "#5D4037", "#FFFBF0", "#F44336", "#FFEBEE", "#D7CCC8", "#F5F5DC", "#795548")
        case .monochrome:
            return p("#FFFFFF", "#111111", "#000000", "#000000", "#111111", "#FFFFFF", "#E0E0E0", "#000000", "#FFB4AB", "#690005", "#888888", "#444444", "#FFFFFF")
        case .custom:
            return FlowThemePalette(
                primary: Color(argb: custom.primary), primaryContainer: Color(argb: custom.surfaceVariant),
                onPrimary: Color(argb: custom.onPrimary), surface: Color(argb: custom.surface),
                surfaceVariant: Color(argb: custom.surfaceVariant), onSurface: Color(argb: custom.onSurface),
                onSurfaceVariant: Color(argb: custom.onSurfaceVariant), background: Color(argb: custom.background),
                error: Color(argb: custom.error), errorContainer: Color(argb: custom.surfaceVariant),
                outline: Color(argb: custom.outline), outlineVariant: Color(argb: custom.outline).opacity(0.6),
                sponsorBlock: Color(hex: "#00D37A")
            )
        case .materialYou:
            #if canImport(UIKit)
            return p(
                uiColor(.systemBlue), uiColor(.secondarySystemBackground), uiColor(.label),
                uiColor(.secondarySystemBackground), uiColor(.tertiarySystemBackground),
                uiColor(.label), uiColor(.secondaryLabel), uiColor(.systemBackground),
                uiColor(.systemRed), uiColor(.secondarySystemBackground),
                uiColor(.separator), uiColor(.opaqueSeparator), uiColor(.systemGreen)
            )
            #else
            return palette(for: .dark)
            #endif
        case .system:
            return palette(for: ThemeManager.shared.systemDarkTheme)
        }
    }

    private static func t(_ primary: String, _ bg: String, _ surface: String, _ text: String, _ text2: String, _ border: String) -> FlowThemePalette {
        p(primary, surface, "#FFFFFF", surface, bg, text, text2, bg, "#EF5350", "#3E1B23", border, border, "#00D37A")
    }

    private static func p(
        _ primary: String, _ primaryContainer: String, _ onPrimary: String,
        _ surface: String, _ surfaceVariant: String, _ onSurface: String, _ onSurfaceVariant: String,
        _ background: String, _ error: String, _ errorContainer: String,
        _ outline: String, _ outlineVariant: String, _ sponsor: String
    ) -> FlowThemePalette {
        FlowThemePalette(
            primary: Color(hex: primary), primaryContainer: Color(hex: primaryContainer),
            onPrimary: Color(hex: onPrimary), surface: Color(hex: surface),
            surfaceVariant: Color(hex: surfaceVariant), onSurface: Color(hex: onSurface),
            onSurfaceVariant: Color(hex: onSurfaceVariant), background: Color(hex: background),
            error: Color(hex: error), errorContainer: Color(hex: errorContainer),
            outline: Color(hex: outline), outlineVariant: Color(hex: outlineVariant),
            sponsorBlock: Color(hex: sponsor)
        )
    }

    #if canImport(UIKit)
    private static func uiColor(_ color: UIColor) -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }
    #endif
}

extension Color {
    init(argb: UInt32) {
        let a = Double((argb >> 24) & 0xFF) / 255
        let r = Double((argb >> 16) & 0xFF) / 255
        let g = Double((argb >> 8) & 0xFF) / 255
        let b = Double(argb & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}

// MARK: - ThemeManager
@Observable
final class ThemeManager {
    static let shared = ThemeManager()

    var themeMode: ThemeMode {
        didSet { defaults.set(themeMode.rawValue, forKey: Keys.themeMode) }
    }

    var systemLightTheme: ThemeMode {
        didSet { defaults.set(systemLightTheme.rawValue, forKey: Keys.systemLight) }
    }

    var systemDarkTheme: ThemeMode {
        didSet { defaults.set(systemDarkTheme.rawValue, forKey: Keys.systemDark) }
    }

    var customColors: CustomThemeColors {
        didSet { customColors.save() }
    }

    var palette: FlowThemePalette {
        FlowThemePalette.palette(for: resolvedMode, custom: customColors)
    }

    var preferredColorScheme: ColorScheme? {
        switch themeMode {
        case .system: return nil
        case .light, .mintLight, .roseLight, .skyLight, .creamLight: return .light
        default: return .dark
        }
    }

    var resolvedMode: ThemeMode {
        if themeMode == .system {
            #if canImport(UIKit)
            let isDark = UITraitCollection.current.userInterfaceStyle == .dark
            return isDark ? systemDarkTheme : systemLightTheme
            #else
            return systemDarkTheme
            #endif
        }
        return themeMode
    }

    private let defaults = UserDefaults.standard
    private enum Keys {
        static let themeMode = "theme_mode"
        static let systemLight = "system_light_theme_mode"
        static let systemDark = "system_dark_theme_mode"
    }

    private init() {
        themeMode = ThemeMode(rawValue: defaults.string(forKey: Keys.themeMode) ?? "") ?? .dark
        systemLightTheme = ThemeMode(rawValue: defaults.string(forKey: Keys.systemLight) ?? "") ?? .light
        systemDarkTheme = ThemeMode(rawValue: defaults.string(forKey: Keys.systemDark) ?? "") ?? .dark
        customColors = CustomThemeColors.fromDefaults()
    }
}

#if canImport(UIKit)
import UIKit
#endif
