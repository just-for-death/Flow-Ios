import SwiftUI
import UniformTypeIdentifiers

// MARK: - SubscriptionsView
struct SubscriptionsView: View {
    @State private var store = SubscriptionStore.shared
    @Environment(FlowAVPlayer.self) private var player
    @State private var showImportPicker = false
    @State private var importMessage: String?
    @State private var showManageGroups = false
    @State private var editingGroup: SubscriptionGroup?

    var body: some View {
        NavigationStack {
            Group {
                if store.channels.isEmpty {
                    emptyState
                } else {
                    feedContent
                }
            }
            .background(FlowTheme.Colors.background)
            .navigationTitle("Subs")
            .toolbarBackground(FlowTheme.Colors.background, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Manage groups") { showManageGroups = true }
                        Button("Import NewPipe JSON") { showImportPicker = true }
                        Button("Refresh Feed") { Task { await store.refreshFeed() } }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundStyle(FlowTheme.Colors.onSurface)
                    }
                }
            }
            .refreshable { await store.refreshFeed() }
            .task { if store.feedVideos.isEmpty { await store.refreshFeed() } }
            .fileImporter(isPresented: $showImportPicker, allowedContentTypes: [.json]) { result in
                if case .success(let url) = result {
                    Task {
                        let count = (try? await ImportService.importSubscriptionsJSON(from: url)) ?? 0
                        importMessage = "Imported \(count) subscriptions"
                        await store.refreshFeed()
                    }
                }
            }
            .alert("Import", isPresented: .init(get: { importMessage != nil }, set: { if !$0 { importMessage = nil } })) {
                Button("OK") { importMessage = nil }
            } message: { Text(importMessage ?? "") }
            .sheet(isPresented: $showManageGroups) {
                ManageSubscriptionGroupsSheet()
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: FlowTheme.Spacing.lg) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 56))
                .foregroundStyle(FlowTheme.Colors.onSurfaceVariant)
            Text("No subscriptions yet")
                .font(FlowTheme.Typography.titleMedium)
                .foregroundStyle(FlowTheme.Colors.onSurface)
            Text("Import from NewPipe or subscribe to channels from search.")
                .font(FlowTheme.Typography.bodyMedium)
                .foregroundStyle(FlowTheme.Colors.onSurfaceVariant)
                .multilineTextAlignment(.center)
                .padding(.horizontal, FlowTheme.Spacing.xl)
            Button("Import NewPipe JSON") { showImportPicker = true }
                .buttonStyle(.borderedProminent)
                .tint(FlowTheme.Colors.primary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var feedContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FlowTheme.Spacing.md) {
                // Group chips (Android-style)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: FlowTheme.Spacing.sm) {
                        FlowChip(label: "All", isSelected: store.selectedGroupName == nil) {
                            store.selectGroup(nil)
                        }
                        ForEach(store.groups) { group in
                            FlowChip(label: group.name, isSelected: store.selectedGroupName == group.name) {
                                store.selectGroup(group.name)
                            }
                        }
                        Button { showManageGroups = true } label: {
                            Image(systemName: "folder.badge.plus")
                                .foregroundStyle(FlowTheme.Colors.primary)
                                .frame(height: 36)
                                .padding(.horizontal, 10)
                                .background(FlowTheme.Colors.surfaceVariant)
                                .clipShape(RoundedRectangle(cornerRadius: FlowTheme.Radius.md))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, FlowTheme.Spacing.md)
                }

                // Channel chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: FlowTheme.Spacing.sm) {
                        ForEach(store.channels.prefix(20)) { ch in
                            VStack(spacing: 4) {
                                AsyncImage(url: URL(string: ch.channelThumbnail)) { img in
                                    img.resizable().aspectRatio(1, contentMode: .fill)
                                } placeholder: {
                                    Circle().fill(FlowTheme.Colors.surfaceVariant)
                                }
                                .frame(width: 48, height: 48)
                                .clipShape(Circle())
                                Text(ch.channelName)
                                    .font(FlowTheme.Typography.labelSmall)
                                    .foregroundStyle(FlowTheme.Colors.onSurfaceVariant)
                                    .lineLimit(1)
                                    .frame(width: 64)
                            }
                        }
                    }
                    .padding(.horizontal, FlowTheme.Spacing.md)
                }

                if store.isRefreshingFeed {
                    ProgressView().frame(maxWidth: .infinity)
                }

                LazyVStack(spacing: FlowTheme.Spacing.sm) {
                    ForEach(store.displayedFeedVideos) { video in
                        HorizontalVideoRow(video: video) { player.play(video: video) }
                    }
                }
                .padding(.horizontal, FlowTheme.Spacing.md)
            }
            .padding(.vertical, FlowTheme.Spacing.sm)
        }
    }
}

// MARK: - Manage groups
private struct ManageSubscriptionGroupsSheet: View {
    @State private var store = SubscriptionStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showCreate = false
    @State private var draftName = ""
    @State private var draftIDs: Set<String> = []
    @State private var editing: SubscriptionGroup?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(store.groups) { group in
                        Button {
                            editing = group
                            draftName = group.name
                            draftIDs = Set(group.channelIDs)
                            showCreate = true
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(group.name).foregroundStyle(FlowTheme.Colors.onSurface)
                                    Text("\(group.channelIDs.count) channels")
                                        .font(FlowTheme.Typography.bodySmall)
                                        .foregroundStyle(FlowTheme.Colors.onSurfaceVariant)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(FlowTheme.Colors.onSurfaceVariant)
                            }
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                store.deleteGroup(named: group.name)
                            } label: { Text("Delete") }
                        }
                    }
                } footer: {
                    Text("Groups filter your subscription feed. Synced via FLOW-SYNC/1.")
                }
            }
            .navigationTitle("Groups")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button("New") {
                        editing = nil
                        draftName = ""
                        draftIDs = []
                        showCreate = true
                    }
                }
            }
            .sheet(isPresented: $showCreate) {
                NavigationStack {
                    Form {
                        TextField("Group name", text: $draftName)
                        Section("Channels") {
                            ForEach(store.channels) { ch in
                                Toggle(ch.channelName, isOn: Binding(
                                    get: { draftIDs.contains(ch.channelID) },
                                    set: { on in
                                        if on { draftIDs.insert(ch.channelID) } else { draftIDs.remove(ch.channelID) }
                                    }
                                ))
                            }
                        }
                    }
                    .navigationTitle(editing == nil ? "New group" : "Edit group")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showCreate = false } }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save") {
                                let name = draftName.trimmingCharacters(in: .whitespaces)
                                guard !name.isEmpty else { return }
                                if let editing {
                                    store.updateGroup(named: editing.name, newName: name, channelIDs: Array(draftIDs))
                                } else {
                                    store.addGroup(SubscriptionGroup(
                                        name: name, channelIDs: Array(draftIDs), sortOrder: store.groups.count, deleted: false
                                    ))
                                }
                                showCreate = false
                            }
                        }
                    }
                }
            }
        }
    }
}
