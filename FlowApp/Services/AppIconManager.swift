import SwiftUI
import UIKit

// MARK: - AppIconManager
/// Alternate launcher icons — mirrors Android AppIconPickerScreen.
enum FlowAppIcon: String, CaseIterable, Identifiable {
    case primary = ""
    case flowRed = "FlowRed"
    case flowLight = "FlowLight"
    case flowPlay = "FlowPlay"
    case amoled = "Amoled"
    case monochrome = "Monochrome"
    case ghost = "Ghost"
    case materialSky = "MaterialSky"
    case materialMint = "MaterialMint"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .primary: return "Default"
        case .flowRed: return "Flow Red"
        case .flowLight: return "Flow Light"
        case .flowPlay: return "Flow Play"
        case .amoled: return "AMOLED"
        case .monochrome: return "Monochrome"
        case .ghost: return "Ghost"
        case .materialSky: return "Material Sky"
        case .materialMint: return "Material Mint"
        }
    }

    var previewColor: Color {
        switch self {
        case .primary, .flowRed: return Color(red: 0.06, green: 0.06, blue: 0.06)
        case .flowLight, .flowPlay, .monochrome: return .white
        case .amoled: return .black
        case .ghost: return Color(red: 0.07, green: 0.07, blue: 0.07)
        case .materialSky: return Color(red: 0.84, green: 0.89, blue: 1.0)
        case .materialMint: return Color(red: 0.78, green: 0.91, blue: 0.83)
        }
    }

    /// Android `app_icon_suffix` interoperability.
    var androidSuffix: String {
        switch self {
        case .primary, .flowRed: return ".IconFlowRed"
        case .flowLight: return ".IconFlowLight"
        case .flowPlay: return ".IconFlowPlay"
        case .amoled: return ".IconAmoled"
        case .monochrome: return ".IconMonochrome"
        case .ghost: return ".IconGhost"
        case .materialSky: return ".IconMaterialSky"
        case .materialMint: return ".IconMaterialMint"
        }
    }

    static func fromStored(_ value: String?) -> FlowAppIcon {
        guard let value, !value.isEmpty else { return .primary }
        if let match = FlowAppIcon.allCases.first(where: { $0.rawValue == value }) { return match }
        if let match = FlowAppIcon.allCases.first(where: { $0.androidSuffix == value }) { return match }
        return .primary
    }
}

@MainActor
enum AppIconManager {
    private static let storageKey = "app_icon_name"

    static var current: FlowAppIcon {
        FlowAppIcon.fromStored(UserDefaults.standard.string(forKey: storageKey))
    }

    static func setIcon(_ icon: FlowAppIcon) async throws {
        guard UIApplication.shared.supportsAlternateIcons else { return }
        let name = icon.rawValue.isEmpty ? nil : icon.rawValue
        try await UIApplication.shared.setAlternateIconName(name)
        UserDefaults.standard.set(icon.rawValue, forKey: storageKey)
        UserDefaults.standard.set(icon.androidSuffix, forKey: "app_icon_suffix")
    }
}
