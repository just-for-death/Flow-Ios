import SwiftUI
import UniformTypeIdentifiers

// MARK: - OnboardingView
/// Android-parity onboarding: Interests → Channels → Import.
struct OnboardingView: View {
    let onComplete: () -> Void

    @Environment(NeuroEngine.self) private var neuro
    @State private var step: Step = .interests
    @State private var selectedTopics: Set<String> = []
    @State private var channelQuery = ""
    @State private var channelResults: [ChannelItem] = []
    @State private var isSearchingChannels = false
    @State private var subscribedIDs: Set<String> = []
    @State private var importMessage: String?
    @State private var isFinishing = false
    @State private var searchTask: Task<Void, Never>?

    private enum Step: Int, CaseIterable {
        case interests, channels, importData
        var title: String {
            switch self {
            case .interests: return "Interests"
            case .channels: return "Channels"
            case .importData: return "Import"
            }
        }
    }

    private var canAdvance: Bool {
        switch step {
        case .interests: return selectedTopics.count >= 3
        case .channels, .importData: return true
        }
    }

    var body: some View {
        ZStack {
            FlowTheme.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                stepIndicator
                    .padding(.horizontal, FlowTheme.Spacing.lg)
                    .padding(.top, FlowTheme.Spacing.md)

                Group {
                    switch step {
                    case .interests: interestsStep
                    case .channels: channelsStep
                    case .importData: importStep
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                bottomBar
            }
        }
        .alert("Import", isPresented: .init(
            get: { importMessage != nil },
            set: { if !$0 { importMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importMessage ?? "")
        }
    }

    // MARK: - Chrome

    private var stepIndicator: some View {
        VStack(alignment: .leading, spacing: FlowTheme.Spacing.sm) {
            Text(step.title)
                .font(FlowTheme.Typography.headlineSmall)
                .foregroundStyle(FlowTheme.Colors.onSurface)
            HStack(spacing: 6) {
                ForEach(Step.allCases, id: \.rawValue) { s in
                    Capsule()
                        .fill(s.rawValue <= step.rawValue ? FlowTheme.Colors.primary : FlowTheme.Colors.outlineVariant)
                        .frame(height: 4)
                }
            }
        }
    }

    private var bottomBar: some View {
        HStack(spacing: FlowTheme.Spacing.md) {
            if step != .interests {
                Button("Back") {
                    withAnimation { step = Step(rawValue: step.rawValue - 1) ?? .interests }
                }
                .foregroundStyle(FlowTheme.Colors.onSurfaceVariant)
            }

            Button("Skip") { advance(skipping: true) }
                .foregroundStyle(FlowTheme.Colors.onSurfaceVariant)

            Spacer()

            Button {
                advance(skipping: false)
            } label: {
                Text(step == .importData ? "Get Started" : "Next")
                    .font(FlowTheme.Typography.titleMedium)
                    .foregroundStyle(.white)
                    .padding(.horizontal, FlowTheme.Spacing.lg)
                    .padding(.vertical, FlowTheme.Spacing.sm)
                    .background(canAdvance && !isFinishing ? FlowTheme.Colors.primary : FlowTheme.Colors.outline)
                    .clipShape(RoundedRectangle(cornerRadius: FlowTheme.Radius.lg))
            }
            .disabled(!canAdvance || isFinishing)
        }
        .padding(FlowTheme.Spacing.lg)
    }

    private func advance(skipping: Bool) {
        if step == .importData {
            finish()
            return
        }
        if skipping || canAdvance {
            if let next = Step(rawValue: step.rawValue + 1) {
                withAnimation { step = next }
            } else {
                finish()
            }
        }
    }

    private func finish() {
        isFinishing = true
        neuro.completeOnboarding(selectedTopics: selectedTopics)
        onComplete()
    }

    // MARK: - Interests

    private var interestsStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FlowTheme.Spacing.lg) {
                Text(selectedTopics.count >= 3
                     ? "Looking good — pick more if you want."
                     : "Pick at least \(3 - selectedTopics.count) more interest\(3 - selectedTopics.count == 1 ? "" : "s").")
                    .font(FlowTheme.Typography.bodyMedium)
                    .foregroundStyle(FlowTheme.Colors.onSurfaceVariant)

                ForEach(NeuroTopicCatalog.categories) { category in
                    VStack(alignment: .leading, spacing: FlowTheme.Spacing.sm) {
                        Label(category.name, systemImage: category.systemImage)
                            .font(FlowTheme.Typography.titleSmall)
                            .foregroundStyle(FlowTheme.Colors.onSurface)
                        FlowWrappingHStack(spacing: 8) {
                            ForEach(category.topics, id: \.self) { topic in
                                topicChip(topic)
                            }
                        }
                    }
                }
            }
            .padding(FlowTheme.Spacing.lg)
        }
    }

    private func topicChip(_ topic: String) -> some View {
        let selected = selectedTopics.contains(topic)
        return Button {
            if selected { selectedTopics.remove(topic) } else { selectedTopics.insert(topic) }
        } label: {
            Text(topic)
                .font(FlowTheme.Typography.labelLarge)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(selected ? FlowTheme.Colors.primary : FlowTheme.Colors.surfaceVariant)
                .foregroundStyle(selected ? Color.white : FlowTheme.Colors.onSurface)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Channels

    private var channelsStep: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(FlowTheme.Colors.onSurfaceVariant)
                TextField("Search channels", text: $channelQuery)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onChange(of: channelQuery) { _, value in
                        scheduleChannelSearch(value)
                    }
            }
            .padding(FlowTheme.Spacing.md)
            .background(FlowTheme.Colors.surfaceVariant)
            .clipShape(RoundedRectangle(cornerRadius: FlowTheme.Radius.md))
            .padding(FlowTheme.Spacing.lg)

            if isSearchingChannels {
                ProgressView().padding()
            }

            List {
                ForEach(channelResults) { channel in
                    HStack(spacing: FlowTheme.Spacing.md) {
                        AsyncImage(url: channel.avatarURL) { img in
                            img.resizable().scaledToFill()
                        } placeholder: {
                            Circle().fill(FlowTheme.Colors.outline)
                        }
                        .frame(width: 44, height: 44)
                        .clipShape(Circle())

                        VStack(alignment: .leading, spacing: 2) {
                            Text(channel.name)
                                .font(FlowTheme.Typography.bodyLarge)
                                .foregroundStyle(FlowTheme.Colors.onSurface)
                            if let subs = channel.subscriberCount {
                                Text(subs)
                                    .font(FlowTheme.Typography.bodySmall)
                                    .foregroundStyle(FlowTheme.Colors.onSurfaceVariant)
                            }
                        }
                        Spacer()
                        Button(subscribedIDs.contains(channel.id) ? "Subscribed" : "Subscribe") {
                            toggleSubscribe(channel)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(subscribedIDs.contains(channel.id) ? FlowTheme.Colors.outline : FlowTheme.Colors.primary)
                        .disabled(subscribedIDs.contains(channel.id))
                    }
                    .listRowBackground(FlowTheme.Colors.surfaceVariant)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private func scheduleChannelSearch(_ query: String) {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            channelResults = []
            return
        }
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { isSearchingChannels = true }
            defer { Task { @MainActor in isSearchingChannels = false } }
            guard let page = try? await InnerTubeClient.shared.search(query: trimmed) else { return }
            let channels = page.results.compactMap { item -> ChannelItem? in
                if case .channel(let c) = item { return c }
                return nil
            }
            await MainActor.run { channelResults = Array(channels.prefix(15)) }
        }
    }

    private func toggleSubscribe(_ channel: ChannelItem) {
        guard !subscribedIDs.contains(channel.id) else { return }
        let sub = ChannelSubscription(
            channelID: channel.id,
            channelName: channel.name,
            channelThumbnail: channel.avatarURL?.absoluteString ?? ""
        )
        SubscriptionStore.shared.subscribe(sub)
        subscribedIDs.insert(channel.id)
    }

    // MARK: - Import

    private var importStep: some View {
        List {
            Section("Backup & Restore") {
                importRow("Flow Backup", types: [.json]) { url in
                    let result = try await ImportService.importFlowBackupJSON(from: url)
                    return "Imported \(result.subscriptions) subs, \(result.history) history"
                }
                importRow("Master Backup", types: [.json, .zip]) { url in
                    let result = try await ImportService.importFlowMasterJSON(from: url)
                    return "Imported master backup (\(result.subscriptions) subs)"
                }
            }
            Section("Subscriptions") {
                importRow("NewPipe subscriptions", types: [.json]) { url in
                    let n = try await ImportService.importSubscriptionsJSON(from: url)
                    return "Imported \(n) subscriptions"
                }
            }
            Section("History") {
                importRow("NewPipe history", types: [.data, .zip]) { url in
                    let n = try await ImportService.importWatchHistoryDatabase(from: url)
                    return "Imported \(n) history items"
                }
            }
            Section {
                Text("You can import more formats later in Settings. Skip if you want a fresh start.")
                    .font(FlowTheme.Typography.bodySmall)
                    .foregroundStyle(FlowTheme.Colors.onSurfaceVariant)
            }
        }
        .scrollContentBackground(.hidden)
    }

    private func importRow(
        _ title: String,
        types: [UTType],
        handler: @escaping (URL) async throws -> String
    ) -> some View {
        ImportPickerButton(title: title, types: types) { url in
            do {
                let msg = try await handler(url)
                await MainActor.run { importMessage = msg }
            } catch {
                await MainActor.run { importMessage = error.localizedDescription }
            }
        }
    }
}

// MARK: - Import picker button
private struct ImportPickerButton: View {
    let title: String
    let types: [UTType]
    let handler: (URL) async -> Void

    @State private var showPicker = false

    var body: some View {
        Button(title) { showPicker = true }
            .foregroundStyle(FlowTheme.Colors.primary)
            .fileImporter(isPresented: $showPicker, allowedContentTypes: types) { result in
                guard case .success(let url) = result else { return }
                let access = url.startAccessingSecurityScopedResource()
                Task {
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    await handler(url)
                }
            }
    }
}

// MARK: - Simple wrapping layout
struct FlowWrappingHStack: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        layout(in: proposal.width ?? 0, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(in: bounds.width, subviews: subviews)
        for (index, origin) in result.origins.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                proposal: .unspecified
            )
        }
    }

    private func layout(in width: CGFloat, subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxWidth: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxWidth = max(maxWidth, x)
        }
        return (CGSize(width: maxWidth, height: y + rowHeight), origins)
    }
}
