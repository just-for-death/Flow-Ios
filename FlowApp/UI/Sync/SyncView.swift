import SwiftUI
import AVFoundation
import CoreImage
import UIKit

// MARK: - SyncView
/// Device-to-device sync UI — mirrors the Android FLOW-SYNC/1 onboarding flow.
struct SyncView: View {
    @Environment(SyncManager.self) private var sync
    @Environment(\.dismiss) private var dismiss
    @State private var mode: SyncMode = .chooser
    @State private var showScanner = false

    enum SyncMode { case chooser, host, join }

    var body: some View {
        NavigationStack {
            ZStack {
                FlowTheme.Colors.background.ignoresSafeArea()
                Group {
                    switch mode {
                    case .chooser: chooserView
                    case .host:   hostView
                    case .join:   joinView
                    }
                }
            }
            .navigationTitle("Sync Devices")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(FlowTheme.Colors.background, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(FlowTheme.Colors.onSurface)
                }
            }
        }
        .preferredColorScheme(.dark)
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

            Text("Transfer your watch history, liked videos, playlists, settings, and FlowNeuro brain between devices over your local Wi-Fi. No internet required.")
                .font(FlowTheme.Typography.bodyMedium)
                .foregroundStyle(FlowTheme.Colors.onSurfaceVariant)
                .multilineTextAlignment(.center)
                .padding(.horizontal, FlowTheme.Spacing.xl)

            Spacer()

            VStack(spacing: FlowTheme.Spacing.md) {
                Button {
                    mode = .host
                } label: {
                    Label("Show QR Code (Host)", systemImage: "qrcode")
                        .font(FlowTheme.Typography.titleMedium)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(FlowTheme.Spacing.md)
                        .background(FlowTheme.Colors.primary)
                        .clipShape(RoundedRectangle(cornerRadius: FlowTheme.Radius.lg))
                }

                Button {
                    mode = .join
                } label: {
                    Label("Scan QR Code (Join)", systemImage: "camera.viewfinder")
                        .font(FlowTheme.Typography.titleMedium)
                        .foregroundStyle(FlowTheme.Colors.primary)
                        .frame(maxWidth: .infinity)
                        .padding(FlowTheme.Spacing.md)
                        .background(FlowTheme.Colors.surfaceVariant)
                        .clipShape(RoundedRectangle(cornerRadius: FlowTheme.Radius.lg))
                }
            }
            .padding(.horizontal, FlowTheme.Spacing.xl)
            .padding(.bottom, FlowTheme.Spacing.xxl)
        }
    }

    // MARK: - Host mode (show QR)
    private var hostView: some View {
        Group {
            switch sync.state {
            case .idle, .discovering:
                SyncHostQRView()
            case .connecting:
                SyncProgressView(message: "Connecting…", progress: nil)
            case .syncing(let p):
                SyncProgressView(message: "Syncing…", progress: p)
            case .done(let peer):
                SyncDoneView(peerName: peer.deviceName) { dismiss() }
            case .failed(let err):
                SyncErrorView(error: err) { mode = .chooser }
            }
        }
    }

    // MARK: - Join mode (scan QR then connect)
    private var joinView: some View {
        Group {
            switch sync.state {
            case .idle, .discovering:
                SyncQRScannerView { payload in
                    guard let data = payload.data(using: .utf8),
                          let qr = try? JSONDecoder().decode(SyncManager.QRPayload.self, from: data),
                          let masterKey = qr.k.base64URLDecodedData(),
                          let sid = qr.sid.base64URLDecodedData() else { return }
                    Task { await sync.syncWithPeer(host: qr.ip, port: qr.p, masterKey: masterKey, sessionID: sid, isHost: false, role: .receiver) }
                }
            case .connecting:
                SyncProgressView(message: "Connecting…", progress: nil)
            case .syncing(let p):
                SyncProgressView(message: "Syncing…", progress: p)
            case .done(let peer):
                SyncDoneView(peerName: peer.deviceName) { dismiss() }
            case .failed(let err):
                SyncErrorView(error: err) { mode = .chooser }
            }
        }
    }
}

// MARK: - SyncHostQRView
import CoreImage.CIFilterBuiltins

struct SyncHostQRView: View {
    @Environment(SyncManager.self) private var sync
    @State private var qrPayload: SyncManager.QRPayload?
    @State private var showSAS   = false

    var body: some View {
        VStack(spacing: FlowTheme.Spacing.lg) {
            Text("On your Android device, go to\nSettings → Sync → Scan QR Code")
                .font(FlowTheme.Typography.bodyMedium)
                .foregroundStyle(FlowTheme.Colors.onSurfaceVariant)
                .multilineTextAlignment(.center)

            if let qrPayload = qrPayload,
               let json = try? JSONEncoder().encode(qrPayload),
               let qrString = String(data: json, encoding: .utf8),
               let uiImage = generateQRCode(from: qrString) {
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

            Text("Waiting for Android to connect…")
                .font(FlowTheme.Typography.bodySmall)
                .foregroundStyle(FlowTheme.Colors.onSurfaceVariant)

            if !sync.sasCode.isEmpty {
                SASConfirmView()
            }
        }
        .padding(FlowTheme.Spacing.xl)
        .onAppear {
            let port: UInt16 = 9340
            let payload = sync.generateQRPayload(listeningPort: port)
            qrPayload = payload
            Task {
                if let key = payload.k.base64URLDecodedData(), let sid = payload.sid.base64URLDecodedData() {
                    await sync.syncWithPeer(host: "0.0.0.0", port: port, masterKey: key, sessionID: sid, isHost: true, role: .sender)
                }
            }
        }
    }

    private func generateQRCode(from string: String) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)

        if let outputImage = filter.outputImage {
            if let cgImage = context.createCGImage(outputImage, from: outputImage.extent) {
                return UIImage(cgImage: cgImage)
            }
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

            // 6-digit code display
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
                Button("Reject") {
                    sync.confirmSAS(false)
                }
                .font(FlowTheme.Typography.labelLarge)
                .foregroundStyle(FlowTheme.Colors.error)
                .frame(maxWidth: .infinity)
                .padding(FlowTheme.Spacing.sm)
                .background(FlowTheme.Colors.errorContainer)
                .clipShape(RoundedRectangle(cornerRadius: FlowTheme.Radius.md))

                Button("Confirm") {
                    sync.confirmSAS(true)
                }
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

// MARK: - QR Scanner (wraps AVFoundation)
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
        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }
        func metadataOutput(_ output: AVCaptureMetadataOutput,
                            didOutput objects: [AVMetadataObject], from connection: AVCaptureConnection) {
            guard let obj = objects.first as? AVMetadataMachineReadableCodeObject,
                  let str = obj.stringValue else { return }
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
