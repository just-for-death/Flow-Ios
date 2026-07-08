import SwiftUI

// MARK: - OnboardingView
/// 5-page onboarding that mirrors the Android app's 6-screen onboarding.
struct OnboardingView: View {

    let onComplete: () -> Void
    @State private var page = 0

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            icon: "play.circle.fill",
            title: "Welcome to Flow",
            body: "A privacy-first YouTube client that learns your taste — no ads, no tracking, no account required.",
            primaryColor: FlowTheme.Colors.primary
        ),
        OnboardingPage(
            icon: "brain.filled.head.profile",
            title: "Flow Learns With You",
            body: "FlowNeuro analyzes what you watch, skip, and like — entirely on your device. Your data never leaves your iPhone.",
            primaryColor: FlowTheme.Colors.primary
        ),
        OnboardingPage(
            icon: "shield.lefthalf.filled",
            title: "SponsorBlock Built In",
            body: "Automatically skips sponsor segments, self-promotion, and outros using the community-driven SponsorBlock database.",
            primaryColor: FlowTheme.Colors.sponsorBlock
        ),
        OnboardingPage(
            icon: "music.note.house.fill",
            title: "Music Player Included",
            body: "A dedicated audio player with synchronized lyrics, album art, background playback, and lock screen controls.",
            primaryColor: FlowTheme.Colors.primary
        ),
        OnboardingPage(
            icon: "lock.shield.fill",
            title: "Fully Open Source",
            body: "Flow is GPL v3 licensed. You can audit, modify, and build it yourself. No black boxes, no hidden analytics.",
            primaryColor: FlowTheme.Colors.primary
        )
    ]

    var body: some View {
        ZStack {
            FlowTheme.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // Page content
                TabView(selection: $page) {
                    ForEach(pages.indices, id: \.self) { idx in
                        OnboardingPageView(p: pages[idx])
                            .tag(idx)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(FlowTheme.Animation.standard, value: page)

                // Dots + navigation
                VStack(spacing: FlowTheme.Spacing.lg) {
                    // Progress dots
                    HStack(spacing: FlowTheme.Spacing.sm) {
                        ForEach(pages.indices, id: \.self) { idx in
                            Capsule()
                                .fill(idx == page ? FlowTheme.Colors.primary : FlowTheme.Colors.outlineVariant)
                                .frame(width: idx == page ? 24 : 8, height: 8)
                                .animation(FlowTheme.Animation.standard, value: page)
                        }
                    }

                    // CTA button
                    Button {
                        if page < pages.count - 1 {
                            withAnimation(FlowTheme.Animation.standard) { page += 1 }
                        } else {
                            onComplete()
                        }
                    } label: {
                        Text(page < pages.count - 1 ? "Continue" : "Get Started")
                            .font(FlowTheme.Typography.titleMedium)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(FlowTheme.Spacing.md)
                            .background(FlowTheme.Colors.primary)
                            .clipShape(RoundedRectangle(cornerRadius: FlowTheme.Radius.lg))
                    }
                    .padding(.horizontal, FlowTheme.Spacing.xl)

                    if page < pages.count - 1 {
                        Button("Skip") { onComplete() }
                            .font(FlowTheme.Typography.bodyMedium)
                            .foregroundStyle(FlowTheme.Colors.onSurfaceVariant)
                    }
                }
                .padding(.bottom, FlowTheme.Spacing.xxl)
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Page model
struct OnboardingPage {
    let icon:         String
    let title:        String
    let body:         String
    let primaryColor: Color
}

// MARK: - Individual page view
struct OnboardingPageView: View {
    let p: OnboardingPage
    @State private var appeared = false

    var body: some View {
        VStack(spacing: FlowTheme.Spacing.xl) {
            Spacer()

            // Icon
            ZStack {
                Circle()
                    .fill(p.primaryColor.opacity(0.12))
                    .frame(width: 140, height: 140)
                Image(systemName: p.icon)
                    .font(.system(size: 68))
                    .foregroundStyle(p.primaryColor)
            }
            .scaleEffect(appeared ? 1 : 0.6)
            .opacity(appeared ? 1 : 0)

            // Text
            VStack(spacing: FlowTheme.Spacing.sm) {
                Text(p.title)
                    .font(FlowTheme.Typography.headlineMedium)
                    .foregroundStyle(FlowTheme.Colors.onSurface)
                    .multilineTextAlignment(.center)

                Text(p.body)
                    .font(FlowTheme.Typography.bodyLarge)
                    .foregroundStyle(FlowTheme.Colors.onSurfaceVariant)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, FlowTheme.Spacing.xl)
            }
            .offset(y: appeared ? 0 : 20)
            .opacity(appeared ? 1 : 0)

            Spacer()
        }
        .onAppear {
            withAnimation(FlowTheme.Animation.emphasize.delay(0.1)) { appeared = true }
        }
        .onDisappear { appeared = false }
    }
}
