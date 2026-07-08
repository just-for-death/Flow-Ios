import SwiftUI

// MARK: - Flow Design Tokens
/// Single source of truth for colors, typography, and spacing.
/// Mirrors the Material 3 color roles used by the Android app
/// but expressed as Apple HIG / SwiftUI primitives.
enum FlowTheme {

    // MARK: Colors
    enum Colors {
        /// Primary brand color — deep indigo
        static let primary          = Color(hex: "#7B61FF")
        /// Lighter variant for backgrounds
        static let primaryContainer = Color(hex: "#1E1B4B")
        /// On-primary text / icon
        static let onPrimary        = Color.white

        /// Surface (card, sheet, player bar)
        static let surface          = Color(hex: "#0F0F1A")
        static let surfaceVariant   = Color(hex: "#1C1C2E")
        static let onSurface        = Color(hex: "#E2E2F0")
        static let onSurfaceVariant = Color(hex: "#A0A0BB")

        /// Background
        static let background       = Color(hex: "#0A0A12")

        /// Error
        static let error            = Color(hex: "#CF6679")

        /// Outline
        static let outline          = Color(hex: "#3A3A5C")
        static let outlineVariant   = Color(hex: "#2A2A44")

        /// SponsorBlock segment color
        static let sponsorBlock     = Color(hex: "#00D37A")
    }

    // MARK: Typography
    enum Type {
        static let displayLarge  = Font.system(size: 57, weight: .regular, design: .rounded)
        static let displayMedium = Font.system(size: 45, weight: .regular, design: .rounded)
        static let headlineLarge = Font.system(size: 32, weight: .semibold, design: .rounded)
        static let headlineMedium = Font.system(size: 28, weight: .semibold, design: .rounded)
        static let headlineSmall = Font.system(size: 24, weight: .semibold, design: .rounded)
        static let titleLarge    = Font.system(size: 22, weight: .medium, design: .rounded)
        static let titleMedium   = Font.system(size: 16, weight: .medium, design: .rounded)
        static let titleSmall    = Font.system(size: 14, weight: .medium, design: .rounded)
        static let bodyLarge     = Font.system(size: 16, weight: .regular)
        static let bodyMedium    = Font.system(size: 14, weight: .regular)
        static let bodySmall     = Font.system(size: 12, weight: .regular)
        static let labelLarge    = Font.system(size: 14, weight: .medium)
        static let labelMedium   = Font.system(size: 12, weight: .medium)
        static let labelSmall    = Font.system(size: 11, weight: .medium)
    }

    // MARK: Spacing
    enum Spacing {
        static let xs:  CGFloat = 4
        static let sm:  CGFloat = 8
        static let md:  CGFloat = 16
        static let lg:  CGFloat = 24
        static let xl:  CGFloat = 32
        static let xxl: CGFloat = 48
    }

    // MARK: Radius
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

// MARK: - FlowChip
struct FlowChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(FlowTheme.Type.labelMedium)
                .foregroundStyle(isSelected ? FlowTheme.Colors.onPrimary : FlowTheme.Colors.onSurfaceVariant)
                .padding(.horizontal, FlowTheme.Spacing.md)
                .padding(.vertical, FlowTheme.Spacing.xs + 2)
                .background(
                    isSelected
                        ? FlowTheme.Colors.primary
                        : FlowTheme.Colors.surfaceVariant
                )
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(
                            isSelected ? Color.clear : FlowTheme.Colors.outline,
                            lineWidth: 0.5
                        )
                )
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
