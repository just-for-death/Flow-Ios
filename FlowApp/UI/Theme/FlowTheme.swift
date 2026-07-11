import SwiftUI

// MARK: - Flow Design Tokens
/// Single source of truth for colors, typography, and spacing.
/// Mirrors the Material 3 color roles used by the Android app
/// but expressed as Apple HIG / SwiftUI primitives.
enum FlowTheme {

    // MARK: Colors — resolved from active theme palette
    enum Colors {
        static var primary:          Color { ThemeManager.shared.palette.primary }
        static var primaryContainer: Color { ThemeManager.shared.palette.primaryContainer }
        static var onPrimary:        Color { ThemeManager.shared.palette.onPrimary }
        static var surface:          Color { ThemeManager.shared.palette.surface }
        static var surfaceVariant:   Color { ThemeManager.shared.palette.surfaceVariant }
        static var onSurface:        Color { ThemeManager.shared.palette.onSurface }
        static var onSurfaceVariant: Color { ThemeManager.shared.palette.onSurfaceVariant }
        static var background:       Color { ThemeManager.shared.palette.background }
        static var error:            Color { ThemeManager.shared.palette.error }
        static var errorContainer:   Color { ThemeManager.shared.palette.errorContainer }
        static var outline:          Color { ThemeManager.shared.palette.outline }
        static var outlineVariant:   Color { ThemeManager.shared.palette.outlineVariant }
        static var sponsorBlock:     Color { ThemeManager.shared.palette.sponsorBlock }
    }

    // MARK: Typography — mirrors Android Type.kt (system default / Roboto-equivalent)
    enum Typography {
        static let displayLarge  = Font.system(size: 34, weight: .bold)
        static let displayMedium = Font.system(size: 28, weight: .bold)
        static let headlineLarge = Font.system(size: 24, weight: .semibold)
        static let headlineMedium = Font.system(size: 20, weight: .semibold)
        static let headlineSmall = Font.system(size: 18, weight: .semibold)
        static let titleLarge    = Font.system(size: 18, weight: .medium)
        static let titleMedium   = Font.system(size: 16, weight: .medium)
        static let titleSmall    = Font.system(size: 14, weight: .medium)
        static let bodyLarge     = Font.system(size: 16, weight: .regular)
        static let bodyMedium    = Font.system(size: 14, weight: .regular)
        static let bodySmall     = Font.system(size: 12, weight: .regular)
        static let labelLarge    = Font.system(size: 14, weight: .medium)
        static let labelMedium   = Font.system(size: 12, weight: .medium)
        static let labelSmall    = Font.system(size: 10, weight: .medium)
        /// Android ExtraBold brand wordmark (FLOW / MUSIC)
        static let brand         = Font.system(size: 22, weight: .heavy)
    }

    // MARK: Spacing — Android Dimensions.kt padding ~12dp base
    enum Spacing {
        static let xs:  CGFloat = 4
        static let sm:  CGFloat = 8
        static let md:  CGFloat = 12
        static let lg:  CGFloat = 16
        static let xl:  CGFloat = 24
        static let xxl: CGFloat = 32
    }

    // MARK: Radius — Android card 8dp, chip 12dp, settings group 16dp
    enum Radius {
        static let sm:   CGFloat = 8
        static let md:   CGFloat = 12
        static let lg:   CGFloat = 16
        static let xl:   CGFloat = 24
        static let pill: CGFloat = 999
    }

    // MARK: Animation
    enum Animation {
        static let standard  = SwiftUI.Animation.spring(response: 0.35, dampingFraction: 0.7)
        static let emphasize = SwiftUI.Animation.spring(response: 0.5, dampingFraction: 0.65)
        static let fast      = SwiftUI.Animation.easeOut(duration: 0.15)
    }
}

// MARK: - Color hex init
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: .alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red:   Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - FlowCard modifier
struct FlowCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(FlowTheme.Colors.surfaceVariant)
            .clipShape(RoundedRectangle(cornerRadius: FlowTheme.Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: FlowTheme.Radius.md)
                    .stroke(FlowTheme.Colors.outlineVariant, lineWidth: 0.5)
            )
    }
}

extension View {
    func flowCard() -> some View {
        modifier(FlowCard())
    }
}

// MARK: - FlowChip (Android ContentFilterChip)
/// 12pt rounded rect; selected = onSurface fill + inverse text (not primary capsule).
struct FlowChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(FlowTheme.Typography.labelMedium)
                .foregroundStyle(isSelected ? FlowTheme.Colors.background : FlowTheme.Colors.onSurface)
                .padding(.horizontal, 14)
                .frame(height: 36)
                .background(isSelected ? FlowTheme.Colors.onSurface : FlowTheme.Colors.surfaceVariant)
                .clipShape(RoundedRectangle(cornerRadius: FlowTheme.Radius.md))
        }
        .buttonStyle(.plain)
        .animation(FlowTheme.Animation.fast, value: isSelected)
    }
}

// MARK: - FlowProgressBar (used on player scrubber)
struct FlowProgressBar: View {
    let progress: Double   // 0…1
    let buffered: Double   // 0…1
    let segments: [SponsorSegment]
    let onScrub: (Double) -> Void

    @State private var isDragging = false
    @State private var dragProgress: Double = 0

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Track
                Capsule()
                    .fill(FlowTheme.Colors.onSurface.opacity(0.15))
                    .frame(height: 4)

                // Buffered
                Capsule()
                    .fill(FlowTheme.Colors.onSurface.opacity(0.3))
                    .frame(width: geo.size.width * buffered, height: 4)

                // Progress
                Capsule()
                    .fill(FlowTheme.Colors.primary)
                    .frame(width: geo.size.width * (isDragging ? dragProgress : progress), height: isDragging ? 6 : 4)

                // SponsorBlock segments
                ForEach(segments) { seg in
                    Capsule()
                        .fill(FlowTheme.Colors.sponsorBlock)
                        .frame(width: max(3, geo.size.width * (seg.end - seg.start)), height: 6)
                        .offset(x: geo.size.width * seg.start)
                }

                // Thumb
                Circle()
                    .fill(FlowTheme.Colors.primary)
                    .frame(width: isDragging ? 18 : 12, height: isDragging ? 18 : 12)
                    .offset(x: geo.size.width * (isDragging ? dragProgress : progress) - (isDragging ? 9 : 6))
            }
            .frame(height: 20)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { val in
                        isDragging = true
                        dragProgress = max(0, min(1, val.location.x / geo.size.width))
                    }
                    .onEnded { _ in
                        onScrub(dragProgress)
                        withAnimation(FlowTheme.Animation.fast) { isDragging = false }
                    }
            )
        }
        .frame(height: 20)
        .animation(FlowTheme.Animation.standard, value: isDragging)
    }
}

// MARK: - FlowChipButtonStyle
struct FlowChipButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(FlowTheme.Colors.surfaceVariant)
            .foregroundStyle(FlowTheme.Colors.onSurface)
            .clipShape(RoundedRectangle(cornerRadius: FlowTheme.Radius.md))
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
    }
}
