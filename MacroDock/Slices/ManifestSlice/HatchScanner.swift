import AVFoundation
import SwiftUI
import UIKit

enum HatchPermission: Equatable {
    case unknown
    case ready
    case denied
    case restricted
    case noDevice
}

/// AVCaptureSession is not Sendable. start/stop are the only concurrent calls
/// and match AVFoundation's documented thread contract for those methods.
final class HatchSessionBox: @unchecked Sendable {
    let session = AVCaptureSession()

    func start() {
        if !session.isRunning {
            session.startRunning()
        }
    }

    func stop() {
        if session.isRunning {
            session.stopRunning()
        }
    }
}

/// Role in MVVM-C: Scan ViewModel. Live AVCaptureMetadataOutput, torch, hatch overlay. Coordinator assigns onSelectProduct.
@MainActor
@Observable
final class HatchScanViewModel: NSObject {
    var onSelectProduct: ((CargoProduct) -> Void)?
    var permission: HatchPermission = .unknown
    var manualCode = ""
    var torchOn = false
    var fault: String?
    var isResolving = false
    var showSpinner = false
    var missingEnergy = false

    let sessionBox = HatchSessionBox()
    var session: AVCaptureSession { sessionBox.session }
    private let store: HarborStore
    private let client: OpenSeaClient
    private let metadata = AVCaptureMetadataOutput()
    private var lastPayload: String?
    private var lastRead = Date.distantPast
    private var observers: [NSObjectProtocol] = []
    private var configured = false

    init(store: HarborStore, client: OpenSeaClient) {
        self.store = store
        self.client = client
        super.init()
    }

    func appear() {
        observeBackground()
        refreshPermission()
        if permission == .ready {
            start()
        }
    }

    func disappear() {
        stop()
        clearObservers()
    }

    func refreshPermission() {
        guard AVCaptureDevice.default(for: .video) != nil else {
            permission = .noDevice
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            permission = .ready
        case .denied:
            permission = .denied
        case .restricted:
            permission = .restricted
        case .notDetermined:
            permission = .unknown
        @unknown default:
            permission = .denied
        }
    }

    func requestPermission() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            Task { @MainActor in
                self?.permission = granted ? .ready : .denied
                if granted { self?.start() }
            }
        }
    }

    func start() {
        configureIfNeeded()
        // Reason: startRunning blocks and must not occupy the main actor.
        let box = sessionBox
        Task.detached(priority: .userInitiated) {
            box.start()
        }
    }

    func stop() {
        let box = sessionBox
        Task.detached(priority: .userInitiated) {
            box.stop()
        }
        setTorch(false)
    }

    func toggleTorch() {
        setTorch(!torchOn)
    }

    func resolveManual() {
        Task { await resolve(raw: manualCode) }
    }

    func resolveSample(_ barcode: String) {
        Task { await resolve(raw: barcode) }
    }

    func retry() {
        fault = nil
        missingEnergy = false
    }

    private func configureIfNeeded() {
        guard !configured, let device = AVCaptureDevice.default(for: .video) else { return }
        session.beginConfiguration()
        if let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) {
            session.addInput(input)
        }
        if session.canAddOutput(metadata) {
            session.addOutput(metadata)
            metadata.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            metadata.metadataObjectTypes = [.ean8, .ean13, .upce, .qr]
        }
        session.commitConfiguration()
        configured = true
    }

    private func setTorch(_ on: Bool) {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else {
            torchOn = false
            return
        }
        do {
            try device.lockForConfiguration()
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
            torchOn = on
        } catch {
            torchOn = false
        }
    }

    private func observeBackground() {
        clearObservers()
        let resign = NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.stop()
            }
        }
        let active = NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                if self?.permission == .ready {
                    self?.start()
                }
            }
        }
        observers = [resign, active]
    }

    private func clearObservers() {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers = []
    }

    private func handlePayload(_ payload: String) {
        let now = Date()
        if payload == lastPayload, now.timeIntervalSince(lastRead) < 1.8 { return }
        if now.timeIntervalSince(lastRead) < 1.8 { return }
        lastPayload = payload
        lastRead = now
        Task { await resolve(raw: payload) }
    }

    private func resolve(raw: String) async {
        let codes = HatchCode.candidates(from: raw)
        guard !codes.isEmpty else {
            fault = "That mark holds no cargo code."
            return
        }
        guard !isResolving else { return }
        isResolving = true
        showSpinner = false
        let spinner = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            self?.showSpinner = true
        }
        defer {
            spinner.cancel()
            isResolving = false
            showSpinner = false
        }
        fault = nil
        missingEnergy = false
        for code in codes {
            if let cached = try? await store.loadProduct(barcode: code) {
                finish(cached)
                return
            }
            if let shelf = LocalHoldShelf.product(barcode: code) {
                try? await store.saveProduct(shelf)
                finish(shelf)
                return
            }
            do {
                let product = try await client.product(code: code)
                try? await store.saveProduct(product)
                finish(product)
                return
            } catch let fault as HarborFault where fault == .notFound {
                continue
            } catch let fault as HarborFault where fault == .cancelled {
                return
            } catch {
                self.fault = "No sea-link, and that code is not in the local hold."
                return
            }
        }
        fault = "The hatch code is not on the open-sea register."
    }

    private func finish(_ product: CargoProduct) {
        if product.kcal100 == nil {
            missingEnergy = true
        }
        onSelectProduct?(product)
    }
}

extension HatchScanViewModel: AVCaptureMetadataOutputObjectsDelegate {
    nonisolated func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        let payload = metadataObjects.compactMap { object in
            (object as? AVMetadataMachineReadableCodeObject)?.stringValue
        }.first
        guard let payload else { return }
        Task { @MainActor in
            self.handlePayload(payload)
        }
    }
}

struct HatchScanView: View {
    @Bindable var model: HatchScanViewModel

    var body: some View {
        NavigationStack {
            VStack(spacing: BerthMetrics.space(2)) {
                cameraRegion
                manual
                if model.showSpinner {
                    ProgressView().tint(TidePalette.ink)
                }
                if let fault = model.fault {
                    TideFaultBanner(message: fault, retry: model.retry)
                }
                if model.missingEnergy {
                    Text("Cargo found, but energy is unknown. You can still berth it.")
                        .font(SignalType.log)
                        .foregroundStyle(TidePalette.muted)
                }
            }
            .padding(BerthMetrics.space(2))
            .background(TidePalette.background)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("CARGO HATCH")
                        .font(SignalType.berth)
                        .kerning(SignalType.headerKerning)
                        .foregroundStyle(TidePalette.ink)
                }
            }
        }
        .tint(TidePalette.ink)
        .onAppear { model.appear() }
        .onDisappear { model.disappear() }
    }

    @ViewBuilder
    private var cameraRegion: some View {
        switch model.permission {
        case .unknown:
            Button("Open the hatch camera") { model.requestPermission() }
                .buttonStyle(HarborActionStyle())
        case .denied:
            permissionCopy(
                "The hatch is sealed. Camera access is denied.",
                settings: true
            )
        case .restricted:
            permissionCopy(
                "The hatch is locked by a parental restriction.",
                settings: true
            )
        case .noDevice:
            VStack(spacing: BerthMetrics.space(1)) {
                Text("No capture device on this deck. Use a sample mark or type a code.")
                    .font(SignalType.log)
                    .foregroundStyle(TidePalette.muted)
                ForEach(LocalHoldShelf.all, id: \.barcode) { product in
                    Button("\(product.name) · \(product.barcode)") {
                        model.resolveSample(product.barcode)
                    }
                    .font(SignalType.log)
                    .foregroundStyle(TidePalette.ink)
                    .frame(maxWidth: .infinity, minHeight: BerthMetrics.tap, alignment: .leading)
                    .padding(.horizontal, BerthMetrics.space(1))
                    .background(TidePalette.surface)
                    .accessibilityLabel("Sample cargo \(product.name)")
                }
            }
        case .ready:
            ZStack {
                HatchPreview(session: model.session)
                Image("mdk_ScanOverlay")
                    .resizable()
                    .scaledToFit()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                VStack {
                    Spacer()
                    Button(model.torchOn ? "Douse torch" : "Strike torch") {
                        model.toggleTorch()
                    }
                    .buttonStyle(HarborActionStyle())
                    .accessibilityLabel(model.torchOn ? "Turn torch off" : "Turn torch on")
                }
                .padding(BerthMetrics.space(1))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 280)
        }
    }

    private func permissionCopy(_ text: String, settings: Bool) -> some View {
        VStack(spacing: BerthMetrics.space(1)) {
            Text(text)
                .font(SignalType.log)
                .foregroundStyle(TidePalette.ink)
                .multilineTextAlignment(.center)
            if settings, let url = URL(string: UIApplication.openSettingsURLString) {
                Link("Open Settings", destination: url)
                    .font(SignalType.cargo)
                    .foregroundStyle(TidePalette.ink)
                    .frame(minHeight: BerthMetrics.tap)
            }
        }
        .padding(BerthMetrics.space(2))
        .background(TidePalette.surface)
    }

    private var manual: some View {
        VStack(alignment: .leading, spacing: BerthMetrics.space(1)) {
            Text("MANUAL MARK")
                .font(SignalType.signal)
                .kerning(SignalType.headerKerning)
                .foregroundStyle(TidePalette.muted)
            TextField("Paste a code or a product URL", text: $model.manualCode)
                .keyboardType(.numbersAndPunctuation)
                .font(SignalType.cargo)
                .foregroundStyle(TidePalette.ink)
                .padding(BerthMetrics.space(1))
                .frame(minHeight: BerthMetrics.tap)
                .background(TidePalette.surface)
                .accessibilityLabel("Manual cargo code")
            Button("Resolve mark") { model.resolveManual() }
                .buttonStyle(HarborActionStyle())
                .disabled(model.isResolving)
        }
    }
}

struct HatchPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.previewLayer.session = session
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

        var previewLayer: AVCaptureVideoPreviewLayer {
            // Programmer invariant: layerClass is AVCaptureVideoPreviewLayer.
            guard let preview = layer as? AVCaptureVideoPreviewLayer else {
                fatalError("HatchPreview layerClass must be AVCaptureVideoPreviewLayer")
            }
            return preview
        }
    }
}
