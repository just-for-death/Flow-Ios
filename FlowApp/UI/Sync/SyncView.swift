import SwiftUI
import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

// MARK: - SyncView
/// Device-to-device sync UI — mirrors Android FLOW-SYNC/1 (role × transport independent).
struct SyncView: View {
    @Environment(SyncManager.self) private var sync
    @Environment(\.dismiss) private var dismiss
    @State private var step: Step = .chooser
    @State private var selectedCollections: Set<String> = Set(SyncCollection.iosSyncable)

    enum Step {
        case chooser
        case sendSelect
        case sendHost
        case sendJoin
        case receiveTransport
        case receiveHost
        case receiveJoin
    }

    private static let collectionKeys = SyncCollection.iosSyncable

    var body: some View {
        NavigationStack {
            ZStack {
                FlowTheme.Colors.background.ignoresSafeArea()
                Group {
                    switch step {
                    case .chooser: chooserView
                    case .sendSelect: sendSelectView
                    case .receiveTransport: receiveTransportView
                    case .sendHost, .receiveHost:
                        hostSessionView(role: step == .sendHost ? .sender : .receiver)
                    case .sendJoin, .receiveJoin:
                        joinSessionView(collections: Array(selectedCollections))
                    }
                }
            }
            .navigationTitle("Sync Devices")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(FlowTheme.Colors.background, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(step == .chooser ? "Cancel" : "Back") {
                        if step == .chooser {
                            dismiss()
                        } else {
                            sync.reset()
                            step = .chooser
                        }
                    }
                    .foregroundStyle(FlowTheme.Colors.onSurface)
                }
            }
            .overlay {
                if !sync.pendingConsentCollections.isEmpty {
                    SyncConsentView()
                        .padding(FlowTheme.Spacing.lg)
                        .background(.ultraThinMaterial)
                }
            }
        }
    }

    // MARK: - Mode chooser
    private var chooserView: some View {
        VStack(spacing: FlowTheme.Spacing.xl) {
            Spacer()

            Image(systemName: "iphone.and.arrow.forward")
                .font(.system(size: 72))
                .foregroundStyle(FlowTheme.Colors.primary)

            Text("Sync with Android")
                .font(FlowTheme.Typography.headlineMedium)
                .foregroundStyle(FlowTheme.Colors.onSurface)

            Text("Transfer watch history, likes, playlists, settings, subscriptions, and FlowNeuro over local Wi‑Fi. Role (send/receive) is independent of who shows the QR.")
                .font(FlowTheme.Typography.bodyMedium)
                .foregroundStyle(FlowTheme.Colors.onSurfaceVariant)
                .multilineTextAlignment(.center)
                .padding(.horizontal, FlowTheme.Spacing.xl)

            Spacer()

            VStack(spacing: FlowTheme.Spacing.md) {
                Button { step = .sendSelect } label: {
                    syncButtonLabel("Send data", systemImage: "square.and.arrow.up", filled: true)
                }
                Button {
                    selectedCollections = Set(Self.collectionKeys)
                    step = .receiveTransport
                } label: {
                    syncButtonLabel("Receive data", systemImage: "square.and.arrow.down", filled: false)
                }
            }
            .padding(.horizontal, FlowTheme.Spacing.xl)
            .padding(.bottom, FlowTheme.Spacing.xxl)
        }
    }

    // MARK: - Send: pick collections then transport
    private var sendSelectView: some View {
        VStack(spacing: FlowTheme.Spacing.lg) {
            Text("Choose what to send")
                .font(FlowTheme.Typography.titleMedium)
                .foregroundStyle(FlowTheme.Colors.onSurface)

            List {
                ForEach(Self.collectionKeys, id: \.self) { key in
                    Button {
                        if selectedCollections.contains(key) {
                            selectedCollections.remove(key)
                        } else {
                            selectedCollections.insert(key)
                        }
                    } label: {
                        HStack {
                            Text(SyncCollection.displayName(for: key))
                                .foregroundStyle(FlowTheme.Colors.onSurface)
                            Spacer()
                            Image(systemName: selectedCollections.contains(key) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(FlowTheme.Colors.primary)
                        }
                    }
                    .listRowBackground(FlowTheme.Colors.surfaceVariant)
                }
            }
            .scrollContentBackground(.hidden)

            VStack(spacing: FlowTheme.Spacing.md) {
                Button {
                    guard !selectedCollections.isEmpty else { return }
                    step = .sendHost
                } label: {
                    syncButtonLabel("Show QR Code", systemImage: "qrcode", filled: true)
                }
                .disabled(selectedCollections.isEmpty)

                Button {
                    guard !selectedCollections.isEmpty else { return }
                    step = .sendJoin
                } label: {
                    syncButtonLabel("Scan QR Code", systemImage: "camera.viewfinder", filled: false)
                }
                .disabled(selectedCollections.isEmpty)
            }
            .padding(.horizontal, FlowTheme.Spacing.xl)
            .padding(.bottom, FlowTheme.Spacing.xl)
        }
            .padding(.top, FlowTheme.Spacing.md)
    }

    private var receiveTransportView: some View {
        VStack(spacing: FlowTheme.Spacing.xl) {
            Spacer()
            Text("How should this device connect?")
                .font(FlowTheme.Typography.titleMedium)
                .foregroundStyle(FlowTheme.Colors.onSurface)
            Text("Show a QR if the other device will scan; scan if the other device is showing a QR.")
                .font(FlowTheme.Typography.bodyMedium)
                .foregroundStyle(FlowTheme.Colors.onSurfaceVariant)
                .multilineTextAlignment(.center)
                .padding(.horizontal, FlowTheme.Spacing.xl)
            Spacer()
            VStack(spacing: FlowTheme.Spacing.md) {
                Button { step = .receiveHost } label: {
                    syncButtonLabel("Show QR Code", systemImage: "qrcode", filled: true)
                }
                Button { step = .receiveJoin } label: {
                    syncButtonLabel("Scan QR Code", systemImage: "camera.viewfinder", filled: false)
                }
            }
            .padding(.horizontal, FlowTheme.Spacing.xl)
            .padding(.bottom, FlowTheme.Spacing.xxl)
        }
    }

    private func hostSessionView(role: FlowSyncProtocol.Role) -> some View {
        Group {
            switch sync.state {
            case .idle, .discovering:
                SyncHostQRView(
                    role: role,
                    collections: role == .sender ? Array(selectedCollections) : SyncCollection.iosSyncable
                )
            case .connecting:
                SyncProgressView(message: "Connecting…", progress: nil)
            case .syncing(let p):
                SyncProgressView(message: "Syncing…", progress: p)
            case .done(let peer):
                SyncDoneView(peerName: peer.deviceName) { dismiss() }
            case .failed(let err):
                SyncErrorView(error: err) { sync.reset(); step = .chooser }
            }
        }
    }

    private func joinSessionView(collections: [String]) -> some View {
        Group {
            switch sync.state {
            case .idle, .discovering:
                VStack(spacing: FlowTheme.Spacing.md) {
                    Text("Scan the QR on the other device")
                        .font(FlowTheme.Typography.bodyMedium)
                        .foregroundStyle(FlowTheme.Colors.onSurfaceVariant)
                    SyncQRScannerView { payload in
                        Task { await sync.joinFromQR(payload, collections: collections) }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: FlowTheme.Radius.lg))
                    .padding()
                }
            case .connecting:
                SyncProgressView(message: "Connecting…", progress: nil)
            case .syncing(let p):
                SyncProgressView(message: "Syncing…", progress: p)
            case .done(let peer):
                SyncDoneView(peerName: peer.deviceName) { dismiss() }
            case .failed(let err):
                SyncErrorView(error: err) { sync.reset(); step = .chooser }
            }
        }
    }

    private func syncButtonLabel(_ title: String, systemImage: String, filled: Bool) -> some View {
        Label(title, systemImage: systemImage)
            .font(FlowTheme.Typography.titleMedium)
            .foregroundStyle(filled ? Color.white : FlowTheme.Colors.primary)
            .frame(maxWidth: .infinity)
            .padding(FlowTheme.Spacing.md)
            .background(filled ? FlowTheme.Colors.primary : FlowTheme.Colors.surfaceVariant)
            .clipShape(RoundedRectangle(cornerRadius: FlowTheme.Radius.lg))
    }
}

// MARK: - SyncHostQRView
struct SyncHostQRView: View {
    @Environment(SyncManager.self) private var sync
    let role: FlowSyncProtocol.Role
    let collections: [String]
    @State private var qrString: String?
    @State private var didStart = false

    var body: some View {
        VStack(spacing: FlowTheme.Spacing.lg) {
            Text(role == .sender
                 ? "On the other device, choose Receive → Scan QR"
                 : "On the other device, choose Send → Scan QR")
                .font(FlowTheme.Typography.bodyMedium)
                .foregroundStyle(FlowTheme.Colors.onSurfaceVariant)
                .multilineTextAlignment(.center)

            if let qrString, let uiImage = generateQRCode(from: qrString) {
                Image(uiImage: uiImage)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 240, height: 240)
                    .clipShape(RoundedRectangle(cornerRadius: FlowTheme.Radius.md))
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: FlowTheme.Radius.lg)
                        .fill(FlowTheme.Colors.surfaceVariant)
                        .frame(width: 240, height: 240)
                    ProgressView()
                }
            }

            Text("Waiting for peer…")
                .font(FlowTheme.Typography.bodySmall)
                .foregroundStyle(FlowTheme.Colors.onSurfaceVariant)

            if !sync.sasCode.isEmpty {
                SASConfirmView()
            }

            if !sync.pendingConsentCollections.isEmpty {
                SyncConsentView()
            }
        }
        .padding(FlowTheme.Spacing.xl)
        .task {
            guard !didStart else { return }
            didStart = true
            if let text = await sync.startHost(role: role, collections: collections) {
                qrString = text
            }
        }
    }

    private func generateQRCode(from string: String) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        if let outputImage = filter.outputImage,
           let cgImage = context.createCGImage(outputImage, from: outputImage.extent) {
            return UIImage(cgImage: cgImage)
        }
        return nil
    }
}

// MARK: - SAS confirmation
struct SASConfirmView: View {
    @Environment(SyncManager.self) private var sync

    var body: some View {
        VStack(spacing: FlowTheme.Spacing.md) {
            Text("Verify Security Code")
                .font(FlowTheme.Typography.titleMedium)
                .foregroundStyle(FlowTheme.Colors.onSurface)

            Text("Does this code match the one shown on your other device?")
                .font(FlowTheme.Typography.bodySmall)
                .foregroundStyle(FlowTheme.Colors.onSurfaceVariant)
                .multilineTextAlignment(.center)

            HStack(spacing: FlowTheme.Spacing.sm) {
                ForEach(Array(sync.sasCode.enumerated()), id: \.0) { _, digit in
                    Text(String(digit))
                        .font(.system(size: 32, weight: .bold, design: .monospaced))
                        .foregroundStyle(FlowTheme.Colors.primary)
                        .frame(width: 44, height: 52)
                        .background(FlowTheme.Colors.surfaceVariant)
                        .clipShape(RoundedRectangle(cornerRadius: FlowTheme.Radius.sm))
                }
            }

            HStack(spacing: FlowTheme.Spacing.md) {
                Button("Reject") { sync.confirmSAS(false) }
                    .font(FlowTheme.Typography.labelLarge)
                    .foregroundStyle(FlowTheme.Colors.error)
                    .frame(maxWidth: .infinity)
                    .padding(FlowTheme.Spacing.sm)
                    .background(FlowTheme.Colors.errorContainer)
                    .clipShape(RoundedRectangle(cornerRadius: FlowTheme.Radius.md))

                Button("Confirm") { sync.confirmSAS(true) }
                    .font(FlowTheme.Typography.labelLarge)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(FlowTheme.Spacing.sm)
                    .background(FlowTheme.Colors.primary)
                    .clipShape(RoundedRectangle(cornerRadius: FlowTheme.Radius.md))
            }
        }
        .padding(FlowTheme.Spacing.md)
        .background(FlowTheme.Colors.surfaceVariant)
        .clipShape(RoundedRectangle(cornerRadius: FlowTheme.Radius.lg))
    }
}

// MARK: - Sync consent
struct SyncConsentView: View {
    @Environment(SyncManager.self) private var sync

    var body: some View {
        VStack(spacing: FlowTheme.Spacing.md) {
            Text("Accept Incoming Data?")
                .font(FlowTheme.Typography.titleMedium)
                .foregroundStyle(FlowTheme.Colors.onSurface)

            Text("The other device wants to merge these collections into this device:")
                .font(FlowTheme.Typography.bodySmall)
                .foregroundStyle(FlowTheme.Colors.onSurfaceVariant)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: FlowTheme.Spacing.xs) {
                ForEach(sync.pendingConsentCollections, id: \.self) { collection in
                    Label(SyncCollection.displayName(for: collection), systemImage: "checkmark.circle")
                        .font(FlowTheme.Typography.bodyMedium)
                        .foregroundStyle(FlowTheme.Colors.onSurface)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: FlowTheme.Spacing.md) {
                Button("Decline") { sync.confirmConsent(false) }
                    .font(FlowTheme.Typography.labelLarge)
                    .foregroundStyle(FlowTheme.Colors.error)
                    .frame(maxWidth: .infinity)
                    .padding(FlowTheme.Spacing.sm)
                    .background(FlowTheme.Colors.errorContainer)
                    .clipShape(RoundedRectangle(cornerRadius: FlowTheme.Radius.md))

                Button("Accept") { sync.confirmConsent(true) }
                    .font(FlowTheme.Typography.labelLarge)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(FlowTheme.Spacing.sm)
                    .background(FlowTheme.Colors.primary)
                    .clipShape(RoundedRectangle(cornerRadius: FlowTheme.Radius.md))
            }
        }
        .padding(FlowTheme.Spacing.md)
        .background(FlowTheme.Colors.surfaceVariant)
        .clipShape(RoundedRectangle(cornerRadius: FlowTheme.Radius.lg))
    }
}

// MARK: - QR Scanner
struct SyncQRScannerView: UIViewRepresentable {
    let onCodeScanned: (String) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        let session = AVCaptureSession()
        guard let device = AVCaptureDevice.default(for: .video),
              let input  = try? AVCaptureDeviceInput(device: device) else { return view }
        session.addInput(input)
        let output = AVCaptureMetadataOutput()
        session.addOutput(output)
        output.setMetadataObjectsDelegate(context.coordinator, queue: .main)
        output.metadataObjectTypes = [.qr]
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.frame = view.bounds
        layer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(layer)
        DispatchQueue.global(qos: .userInitiated).async { session.startRunning() }
        context.coordinator.previewLayer = layer
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.previewLayer?.frame = uiView.bounds
    }

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCodeScanned) }

    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        let onCode: (String) -> Void
        var previewLayer: AVCaptureVideoPreviewLayer?
        private var didFire = false
        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }
        func metadataOutput(_ output: AVCaptureMetadataOutput,
                            didOutput objects: [AVMetadataObject], from connection: AVCaptureConnection) {
            guard !didFire,
                  let obj = objects.first as? AVMetadataMachineReadableCodeObject,
                  let str = obj.stringValue else { return }
            didFire = true
            onCode(str)
        }
    }
}

// MARK: - Status views
struct SyncProgressView: View {
    let message:  String
    let progress: Double?

    var body: some View {
        VStack(spacing: FlowTheme.Spacing.lg) {
            Spacer()
            ProgressView()
                .scaleEffect(2)
                .tint(FlowTheme.Colors.primary)
            Text(message)
                .font(FlowTheme.Typography.titleMedium)
                .foregroundStyle(FlowTheme.Colors.onSurface)
            if let p = progress {
                ProgressView(value: p)
                    .tint(FlowTheme.Colors.primary)
                    .padding(.horizontal, FlowTheme.Spacing.xl)
                Text("\(Int(p * 100))%")
                    .font(FlowTheme.Typography.bodySmall)
                    .foregroundStyle(FlowTheme.Colors.onSurfaceVariant)
            }
            Spacer()
        }
    }
}

struct SyncDoneView: View {
    let peerName: String
    let onDismiss: () -> Void
    var body: some View {
        VStack(spacing: FlowTheme.Spacing.lg) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(FlowTheme.Colors.primary)
            Text("Sync Complete")
                .font(FlowTheme.Typography.headlineMedium)
                .foregroundStyle(FlowTheme.Colors.onSurface)
            Text("Successfully synced with \(peerName)")
                .font(FlowTheme.Typography.bodyMedium)
                .foregroundStyle(FlowTheme.Colors.onSurfaceVariant)
            Spacer()
            Button("Done") { onDismiss() }
                .font(FlowTheme.Typography.titleMedium)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(FlowTheme.Spacing.md)
                .background(FlowTheme.Colors.primary)
                .clipShape(RoundedRectangle(cornerRadius: FlowTheme.Radius.lg))
                .padding(.horizontal, FlowTheme.Spacing.xl)
                .padding(.bottom, FlowTheme.Spacing.xxl)
        }
    }
}

struct SyncErrorView: View {
    let error:   Error
    let onRetry: () -> Void
    var body: some View {
        VStack(spacing: FlowTheme.Spacing.lg) {
            Spacer()
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 80))
                .foregroundStyle(FlowTheme.Colors.error)
            Text("Sync Failed")
                .font(FlowTheme.Typography.headlineMedium)
                .foregroundStyle(FlowTheme.Colors.onSurface)
            Text(error.localizedDescription)
                .font(FlowTheme.Typography.bodySmall)
                .foregroundStyle(FlowTheme.Colors.onSurfaceVariant)
                .multilineTextAlignment(.center)
                .padding(.horizontal, FlowTheme.Spacing.xl)
            Spacer()
            Button("Try Again") { onRetry() }
                .font(FlowTheme.Typography.titleMedium)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(FlowTheme.Spacing.md)
                .background(FlowTheme.Colors.primary)
                .clipShape(RoundedRectangle(cornerRadius: FlowTheme.Radius.lg))
                .padding(.horizontal, FlowTheme.Spacing.xl)
                .padding(.bottom, FlowTheme.Spacing.xxl)
        }
    }
}
