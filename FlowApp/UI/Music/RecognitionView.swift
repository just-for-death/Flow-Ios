import SwiftUI

// MARK: - RecognitionView
struct RecognitionView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var service = RecognitionService.shared
    @State private var isRunning = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if isRunning || service.isListening {
                        HStack {
                            ProgressView()
                            Text("Listening…")
                        }
                    } else if let result = service.lastResult {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(result.title)
                                .font(FlowTheme.Typography.titleMedium)
                            if !result.artist.isEmpty {
                                Text(result.artist)
                                    .foregroundStyle(FlowTheme.Colors.onSurfaceVariant)
                            }
                        }
                    } else if let err = service.lastError {
                        Text(err)
                            .foregroundStyle(FlowTheme.Colors.error)
                    } else {
                        Text("Tap Identify to recognize music playing nearby.")
                            .foregroundStyle(FlowTheme.Colors.onSurfaceVariant)
                    }
                }

                Section("History") {
                    if RecognitionHistoryStore.shared.entries.isEmpty {
                        Text("No recognitions yet")
                            .foregroundStyle(FlowTheme.Colors.onSurfaceVariant)
                    } else {
                        ForEach(RecognitionHistoryStore.shared.entries) { entry in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.title)
                                if !entry.artist.isEmpty {
                                    Text(entry.artist)
                                        .font(FlowTheme.Typography.bodySmall)
                                        .foregroundStyle(FlowTheme.Colors.onSurfaceVariant)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Identify Song")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Identify") {
                        Task {
                            isRunning = true
                            _ = await service.recognize()
                            isRunning = false
                        }
                    }
                    .disabled(isRunning || service.isListening)
                }
            }
        }
    }
}
