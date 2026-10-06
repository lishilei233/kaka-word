import AVFoundation
import Foundation
import PhotosUI
import SwiftUI

/// 将基于 AVFoundation 的相机控制器桥接到 SwiftUI。
struct CameraView: UIViewControllerRepresentable {
    let onImage: (CapturedPhoto) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> CameraViewController {
        let controller = CameraViewController()
        controller.onImage = onImage
        controller.onCancel = onCancel
        return controller
    }

    func updateUIViewController(_ uiViewController: CameraViewController, context: Context) {}
}

final class CameraViewController: UIViewController, UIGestureRecognizerDelegate {
    var onImage: ((CapturedPhoto) -> Void)?
    var onCancel: (() -> Void)?

    private var captureState = CameraCaptureState()
    private let photoBackdrop = UIView()
    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.pictureword.camera.session", qos: .userInitiated)
    private let output = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let videoFrameQueue = DispatchQueue(label: "com.pictureword.camera.video-frame", qos: .userInitiated)
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var captureDevice: AVCaptureDevice?
    private var isSessionConfigured = false
    private var previewCheckToken = UUID()
    private var hasReceivedFirstVideoFrame = false
    private let guideView = CameraGuideView()
    private let shutter = UIButton(type: .custom)
    private let headerState = CameraHeaderState()
    private var headerController: UIHostingController<CameraPageHeader>?
    private let libraryButton = UIButton(type: .system)
    private let cameraStatusView = UIStackView()
    private let cameraStatusIcon = UIImageView()
    private let cameraStatusLabel = UILabel()
    private let cameraStatusActionButton = UIButton(type: .system)
    private var cameraStatusPanel: UIVisualEffectView?
    private var cameraStatusAction: CameraStatusAction = .none
    private var flashMode: AVCaptureDevice.FlashMode = .off
    private let zoomStack = UIStackView()
    private let zoomValueLabel = UILabel()
    private var zoomPanel: UIView?
    private var zoomConfiguration: CameraZoomConfiguration?
    private var cameraIsReady = false
    private var zoomObservations: [NSKeyValueObservation] = []
    // Access only on sessionQueue, alongside every device configuration change.
    private var zoomLocked = false
    private var pinchStartFactor: CGFloat?


    private enum CameraStatusAction {
        case none
        case retry
        case settings
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(Color.paper)
        installPreviewLayer()
        addControls()
        addZoomControls()
        // 状态卡必须位于取景辅助层上方，否则无镜头时会只看到黑色背景。
        addCameraStatus()
        observeSessionLifecycle()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        authorizeAndStartCamera()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopSession()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // CALayer 不参与 Auto Layout，旋转或安全区变化后需要手动同步尺寸。
        let safe = view.safeAreaInsets
        let availableHeight = max(1, view.bounds.height - safe.top - safe.bottom - 300)
        let width = min(view.bounds.width - 40, availableHeight * 0.75)
        let photoRect = CGRect(x: (view.bounds.width - width) / 2,
                               y: safe.top + 82, width: width, height: width / 0.75)
        previewLayer?.frame = photoRect
        photoBackdrop.frame = photoRect.insetBy(dx: -5, dy: -5)
        if let connection = previewLayer?.connection {
            if connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
        }
        updateGuideFrame()
        layoutZoomControls()
    }

    private func updateGuideFrame() {
        guard let previewLayer else { return }

        // 当前 SDK 没有公开 previewLayer.videoRect，这里根据实际输出尺寸计算
        // resizeAspect 后真正显示摄像头画面的区域。
        guard let previewVideoRect = previewVideoRect() else {
            guideView.isHidden = true
            return
        }
        // 辅助层只覆盖这块区域，避免网格线和取景框落到黑边及控制区。
        let videoRect = view.layer.convert(previewVideoRect, from: previewLayer)
        guard videoRect.width > 0, videoRect.height > 0 else {
            guideView.isHidden = true
            return
        }

        guideView.frame = videoRect.integral
        guideView.isHidden = false
        guideView.setNeedsLayout()
    }

    private func previewVideoRect() -> CGRect? {
        guard let previewLayer,
              let formatDescription = captureDevice?.activeFormat.formatDescription else { return nil }

        let dimensions = CMVideoFormatDescriptionGetDimensions(formatDescription)
        guard dimensions.width > 0, dimensions.height > 0,
              previewLayer.bounds.width > 0, previewLayer.bounds.height > 0 else { return nil }

        var videoWidth = CGFloat(dimensions.width)
        var videoHeight = CGFloat(dimensions.height)
        let rotationAngle = previewLayer.connection?.videoRotationAngle ?? 0
        if Int(rotationAngle.rounded()) % 180 != 0 {
            swap(&videoWidth, &videoHeight)
        }

        let videoAspectRatio = videoWidth / videoHeight
        let layerBounds = previewLayer.bounds
        let layerAspectRatio = layerBounds.width / layerBounds.height
        if layerAspectRatio > videoAspectRatio {
            let height = layerBounds.height
            let width = height * videoAspectRatio
            return CGRect(
                x: layerBounds.midX - width / 2,
                y: layerBounds.minY,
                width: width,
                height: height
            )
        } else {
            let width = layerBounds.width
            let height = width / videoAspectRatio
            return CGRect(
                x: layerBounds.minX,
                y: layerBounds.midY - height / 2,
                width: width,
                height: height
            )
        }
    }

    private func installPreviewLayer() {
        photoBackdrop.backgroundColor = UIColor(Color.paperLight)
        photoBackdrop.layer.cornerRadius = 26
        photoBackdrop.layer.borderWidth = 1
        photoBackdrop.layer.borderColor = UIColor(Color.pencil).withAlphaComponent(0.2).cgColor
        view.addSubview(photoBackdrop)
        let layer = AVCaptureVideoPreviewLayer(session: session)
        // 完整展示 4:3 传感器画面，避免全屏 aspectFill 裁掉左右两侧而产生“2× 变焦”错觉。
        layer.videoGravity = .resizeAspect
        layer.backgroundColor = UIColor.clear.cgColor
        layer.frame = view.bounds
        previewLayer = layer
        layer.cornerRadius = 22
        layer.masksToBounds = true
        view.layer.insertSublayer(layer, above: photoBackdrop.layer)
    }

    private func addCameraStatus() {
        cameraStatusIcon.image = UIImage(systemName: "camera.aperture", withConfiguration: UIImage.SymbolConfiguration(pointSize: 32, weight: .bold))
        cameraStatusIcon.tintColor = UIColor(Color.sun)

        cameraStatusLabel.text = "正在启动相机…"
        cameraStatusLabel.textColor = UIColor(Color.ink).withAlphaComponent(0.72)
        cameraStatusLabel.font = .systemFont(ofSize: 15, weight: .bold)
        cameraStatusLabel.numberOfLines = 0
        cameraStatusLabel.textAlignment = .center

        var actionConfiguration = UIButton.Configuration.filled()
        actionConfiguration.baseForegroundColor = .white
        actionConfiguration.baseBackgroundColor = UIColor(Color.coral)
        actionConfiguration.cornerStyle = .capsule
        actionConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 18, bottom: 8, trailing: 18)
        actionConfiguration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var copy = attributes
            copy.font = .systemFont(ofSize: 14, weight: .bold)
            return copy
        }
        cameraStatusActionButton.configuration = actionConfiguration
        cameraStatusActionButton.isHidden = true
        cameraStatusActionButton.addAction(UIAction { [weak self] _ in self?.performCameraStatusAction() }, for: .touchUpInside)

        cameraStatusView.axis = .vertical
        cameraStatusView.alignment = .center
        cameraStatusView.spacing = 14
        cameraStatusView.addArrangedSubview(cameraStatusIcon)
        cameraStatusView.addArrangedSubview(cameraStatusLabel)
        cameraStatusView.addArrangedSubview(cameraStatusActionButton)
        cameraStatusView.translatesAutoresizingMaskIntoConstraints = false

        let panel = glassPanel(cornerRadius: 26)
        cameraStatusPanel = panel
        panel.contentView.addSubview(cameraStatusView)
        view.addSubview(panel)
        NSLayoutConstraint.activate([
            panel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            panel.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -18),
            panel.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, constant: -64),
            cameraStatusView.leadingAnchor.constraint(equalTo: panel.contentView.leadingAnchor, constant: 24),
            cameraStatusView.trailingAnchor.constraint(equalTo: panel.contentView.trailingAnchor, constant: -24),
            cameraStatusView.topAnchor.constraint(equalTo: panel.contentView.topAnchor, constant: 22),
            cameraStatusView.bottomAnchor.constraint(equalTo: panel.contentView.bottomAnchor, constant: -22),
        ])
    }

    private func observeSessionLifecycle() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sessionRuntimeError(_:)),
            name: AVCaptureSession.runtimeErrorNotification,
            object: session
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sessionWasInterrupted(_:)),
            name: AVCaptureSession.wasInterruptedNotification,
            object: session
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sessionInterruptionEnded(_:)),
            name: AVCaptureSession.interruptionEndedNotification,
            object: session
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    private func authorizeAndStartCamera() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndStartSession()
        case .notDetermined:
            showCameraStatus(message: "等待相机权限…", symbol: "camera.aperture")
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self, self.viewIfLoaded?.window != nil else { return }
                    if granted {
                        self.configureAndStartSession()
                    } else {
                        self.showPermissionError()
                    }
                }
            }
        case .denied, .restricted:
            showPermissionError()
        @unknown default:
            showCameraUnavailable()
        }
    }

    private func configureAndStartSession() {
        showCameraStatus(message: "正在连接镜头…", symbol: "camera.aperture")
        hasReceivedFirstVideoFrame = false
        sessionQueue.async { [weak self] in
            guard let self else { return }

            if !self.isSessionConfigured {
                self.session.beginConfiguration()
                self.session.sessionPreset = .photo

                guard let device = [AVCaptureDevice.DeviceType.builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera, .builtInWideAngleCamera]
                    .compactMap({ AVCaptureDevice.default($0, for: .video, position: .back) }).first,
                      let input = try? AVCaptureDeviceInput(device: device),
                      self.session.canAddInput(input),
                      self.session.canAddOutput(self.output),
                      self.session.canAddOutput(self.videoOutput) else {
                    self.session.commitConfiguration()
                    DispatchQueue.main.async { [weak self] in self?.showCameraUnavailable() }
                    return
                }

                self.captureDevice = device
                self.session.addInput(input)
                self.session.addOutput(self.output)
                self.videoOutput.alwaysDiscardsLateVideoFrames = true
                self.videoOutput.setSampleBufferDelegate(self, queue: self.videoFrameQueue)
                self.session.addOutput(self.videoOutput)
                self.output.maxPhotoQualityPrioritization = .quality
                self.session.commitConfiguration()
                self.isSessionConfigured = true
                do {
                    try device.lockForConfiguration()
                    device.videoZoomFactor = self.zoomConfiguration(for: device).deviceFactor(for: 1)
                    device.unlockForConfiguration()
                } catch { self.reportZoomError() }
                self.observeZoom(on: device)
            }

            self.zoomLocked = false
            self.publishZoomState()
            if self.session.isRunning {
                DispatchQueue.main.async { self.startPreviewReadinessCheck() }
                return
            }
            self.session.startRunning()
            DispatchQueue.main.async {
                if self.session.isRunning {
                    self.startPreviewReadinessCheck()
                } else {
                    self.showCameraStatus(
                        message: "镜头启动失败，请重试或从相册选择。",
                        symbol: "exclamationmark.camera.fill",
                        action: .retry
                    )
                }
            }
        }
    }

    private func stopSession() {
        previewCheckToken = UUID()
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    private func addControls() {
        // guideView 根据预览层的 videoRect 手动布局，不参与全屏 Auto Layout。
        guideView.translatesAutoresizingMaskIntoConstraints = true
        guideView.isUserInteractionEnabled = false
        view.addSubview(guideView)

        let header = UIHostingController(rootView: CameraPageHeader(
            state: headerState,
            onClose: { [weak self] in self?.onCancel?() },
            onFlash: { [weak self] in self?.toggleFlash() }
        ))
        header.safeAreaRegions = []
        header.view.backgroundColor = .clear
        header.view.translatesAutoresizingMaskIntoConstraints = false
        addChild(header)
        view.addSubview(header.view)
        header.didMove(toParent: self)
        headerController = header
        NSLayoutConstraint.activate([
            header.view.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            header.view.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            header.view.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            header.view.heightAnchor.constraint(equalToConstant: 76),
        ])

        let hintIcon = UIImageView(image: UIImage(systemName: "viewfinder", withConfiguration: UIImage.SymbolConfiguration(weight: .bold)))
        hintIcon.tintColor = UIColor(Color.ink)
        let hintLabel = UILabel()
        hintLabel.text = "让物品留在取景框里"
        hintLabel.textColor = UIColor(Color.ink)
        hintLabel.font = UIFontMetrics(forTextStyle: .caption1).scaledFont(for: .systemFont(ofSize: 13, weight: .semibold), maximumPointSize: 17)
        hintLabel.adjustsFontForContentSizeCategory = true
        let hintStack = UIStackView(arrangedSubviews: [hintIcon, hintLabel])
        hintStack.axis = .horizontal
        hintStack.spacing = 8
        hintStack.alignment = .center
        hintStack.translatesAutoresizingMaskIntoConstraints = false
        let hintGlass = glassPanel(cornerRadius: 21)
        hintGlass.contentView.addSubview(hintStack)
        NSLayoutConstraint.activate([
            hintStack.leadingAnchor.constraint(equalTo: hintGlass.contentView.leadingAnchor, constant: 14),
            hintStack.trailingAnchor.constraint(equalTo: hintGlass.contentView.trailingAnchor, constant: -14),
            hintStack.centerYAnchor.constraint(equalTo: hintGlass.contentView.centerYAnchor),
            hintGlass.heightAnchor.constraint(equalToConstant: 42),
        ])
        view.addSubview(hintGlass)

        let gridButton = UIButton(type: .system)
        gridButton.setImage(UIImage(systemName: "grid", withConfiguration: UIImage.SymbolConfiguration(weight: .bold)), for: .normal)
        gridButton.tintColor = UIColor(Color.ink)
        gridButton.accessibilityLabel = "切换取景网格"
        gridButton.addAction(UIAction { [weak self, weak gridButton] _ in
            guard let self else { return }
            self.guideView.isGridVisible.toggle()
            gridButton?.tintColor = self.guideView.isGridVisible
                ? UIColor(Color.sun)
                : UIColor(Color.ink)
        }, for: .touchUpInside)
        gridButton.widthAnchor.constraint(equalToConstant: 58).isActive = true
        gridButton.heightAnchor.constraint(equalToConstant: 50).isActive = true

        shutter.backgroundColor = UIColor(Color.sun)
        shutter.layer.cornerRadius = 38
        shutter.layer.borderWidth = 5
        shutter.layer.borderColor = UIColor(Color.paperLight).cgColor
        shutter.layer.shadowColor = UIColor.black.cgColor
        shutter.layer.shadowOpacity = 0.24
        shutter.layer.shadowRadius = 12
        shutter.layer.shadowOffset = CGSize(width: 0, height: 6)
        shutter.isEnabled = false
        shutter.alpha = 0.62
        shutter.accessibilityLabel = "拍照"
        shutter.addAction(UIAction { [weak self] _ in self?.capture() }, for: .touchUpInside)

        var libraryConfiguration = UIButton.Configuration.plain()
        libraryConfiguration.image = UIImage(systemName: "photo.on.rectangle.angled", withConfiguration: UIImage.SymbolConfiguration(weight: .bold))
        // libraryConfiguration.title = "相册"
        libraryConfiguration.imagePlacement = .top
        libraryConfiguration.imagePadding = 4
        libraryConfiguration.baseForegroundColor = UIColor(Color.ink)
        libraryConfiguration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var copy = attributes
            copy.font = .systemFont(ofSize: 11, weight: .bold)
            return copy
        }
        libraryButton.configuration = libraryConfiguration
        libraryButton.accessibilityLabel = "从相册选择照片"
        libraryButton.addAction(UIAction { [weak self] _ in self?.presentPhotoPicker() }, for: .touchUpInside)
        libraryButton.widthAnchor.constraint(equalToConstant: 58).isActive = true
        libraryButton.heightAnchor.constraint(equalToConstant: 58).isActive = true

        let bottomStack = UIStackView(arrangedSubviews: [gridButton, shutter, libraryButton])
        bottomStack.axis = .horizontal
        bottomStack.alignment = .center
        bottomStack.distribution = .equalCentering
        bottomStack.translatesAutoresizingMaskIntoConstraints = false
        let bottomGlass = UIVisualEffectView(effect: nil)
        bottomGlass.translatesAutoresizingMaskIntoConstraints = false
        bottomGlass.contentView.addSubview(bottomStack)
        view.addSubview(bottomGlass)

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinchZoom(_:)))
        pinch.delegate = self
        view.addGestureRecognizer(pinch)
        let focusTap = UITapGestureRecognizer(target: self, action: #selector(focus(at:)))
        focusTap.cancelsTouchesInView = false
        focusTap.delegate = self
        focusTap.require(toFail: pinch)
        view.addGestureRecognizer(focusTap)

        let backSwipe = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(edgeSwipeBack(_:)))
        backSwipe.edges = .left
        view.addGestureRecognizer(backSwipe)

        NSLayoutConstraint.activate([
            hintGlass.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            hintGlass.bottomAnchor.constraint(equalTo: bottomGlass.topAnchor, constant: -14),

            bottomGlass.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            bottomGlass.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            bottomGlass.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
            bottomGlass.heightAnchor.constraint(equalToConstant: 102),
            bottomStack.leadingAnchor.constraint(equalTo: bottomGlass.contentView.leadingAnchor, constant: 24),
            bottomStack.trailingAnchor.constraint(equalTo: bottomGlass.contentView.trailingAnchor, constant: -24),
            bottomStack.centerYAnchor.constraint(equalTo: bottomGlass.contentView.centerYAnchor),
            shutter.centerXAnchor.constraint(equalTo: bottomGlass.contentView.centerXAnchor),
            shutter.widthAnchor.constraint(equalToConstant: 76),
            shutter.heightAnchor.constraint(equalToConstant: 76),
        ])
    }

    private func addZoomControls() {
        zoomStack.axis = .horizontal
        zoomStack.alignment = .center
        zoomStack.spacing = 4
        zoomStack.translatesAutoresizingMaskIntoConstraints = false
        zoomStack.addArrangedSubview(zoomValueLabel)
        zoomValueLabel.font = UIFontMetrics(forTextStyle: .caption1).scaledFont(
            for: .monospacedDigitSystemFont(ofSize: 12, weight: .bold), maximumPointSize: 16
        )
        zoomValueLabel.adjustsFontForContentSizeCategory = true
        zoomValueLabel.textColor = UIColor(Color.ink)
        zoomValueLabel.textAlignment = .center
        zoomValueLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        let panel = UIView()
        panel.backgroundColor = UIColor(Color.sun).withAlphaComponent(0.55)
        panel.layer.cornerRadius = 7
        panel.layer.cornerCurve = .continuous
        panel.layer.borderWidth = 1
        panel.layer.borderColor = UIColor(Color.ink).withAlphaComponent(0.1).cgColor
        panel.layer.shadowColor = UIColor(Color.ink).cgColor
        panel.layer.shadowOpacity = 0.12
        panel.layer.shadowRadius = 3
        panel.layer.shadowOffset = CGSize(width: 0, height: 2)
        panel.transform = CGAffineTransform(rotationAngle: -.pi / 36)
        panel.addSubview(zoomStack)
        let tape = UIView()
        tape.backgroundColor = UIColor(Color.paperDeep).withAlphaComponent(0.9)
        tape.layer.cornerRadius = 1
        tape.transform = CGAffineTransform(rotationAngle: .pi / 30)
        tape.translatesAutoresizingMaskIntoConstraints = false
        tape.isAccessibilityElement = false
        panel.addSubview(tape)
        view.addSubview(panel)
        zoomPanel = panel
        panel.isHidden = true
        panel.isUserInteractionEnabled = false
        NSLayoutConstraint.activate([
            zoomStack.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 8),
            zoomStack.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -8),
            zoomStack.topAnchor.constraint(equalTo: panel.topAnchor, constant: 4),
            zoomStack.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -4),
            zoomValueLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 44),
            tape.widthAnchor.constraint(equalToConstant: 28),
            tape.heightAnchor.constraint(equalToConstant: 8),
            tape.centerXAnchor.constraint(equalTo: panel.centerXAnchor),
            tape.centerYAnchor.constraint(equalTo: panel.topAnchor),
        ])
    }

    private func layoutZoomControls() {
        guard let panel = zoomPanel else { return }
        let size = zoomStack.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        let width = max(size.width + 16, 60)
        // Position against the paper frame, outside the captured image. Setting bounds
        // and center avoids ambiguous frames on the slightly rotated sticker.
        panel.bounds = CGRect(x: 0, y: 0, width: width, height: 30)
        panel.center = CGPoint(x: photoBackdrop.frame.maxX - width / 2 - 12,
                               y: photoBackdrop.frame.maxY + 24)
    }

    private func updateZoomAvailability() {
        headerState.flashEnabled = cameraIsReady && !captureState.isBusy && captureDevice?.hasFlash == true
        let enabled = cameraIsReady && !captureState.isBusy && zoomConfiguration != nil
        zoomPanel?.isHidden = !cameraIsReady || zoomConfiguration == nil
        zoomPanel?.isUserInteractionEnabled = false
        zoomPanel?.alpha = enabled ? 1 : 0.5
    }

    private func renderZoom(configuration: CameraZoomConfiguration, factor: CGFloat) {
        zoomConfiguration = configuration
        let display = configuration.displayFactor(for: factor)
        zoomValueLabel.text = CameraZoomConfiguration.label(for: display)
        zoomValueLabel.accessibilityLabel = "当前镜头倍率 " + CameraZoomConfiguration.label(for: display)
        updateZoomAvailability()
        layoutZoomControls()
    }

    private func zoomConfiguration(for device: AVCaptureDevice) -> CameraZoomConfiguration {
        let switches = device.virtualDeviceSwitchOverVideoZoomFactors.map { CGFloat(truncating: $0) }
        let wideIndex = device.constituentDevices.firstIndex { $0.deviceType == .builtInWideAngleCamera } ?? 0
        let legacyMultiplier = CameraZoomConfiguration.legacyMultiplier(wideIndex: wideIndex, switchFactors: switches)
        let multiplier: CGFloat
        if #available(iOS 18.0, *) {
            multiplier = device.displayVideoZoomFactorMultiplier
        } else {
            multiplier = legacyMultiplier
        }
        return CameraZoomConfiguration(multiplier: multiplier,
                                       minimum: device.minAvailableVideoZoomFactor,
                                       maximum: device.maxAvailableVideoZoomFactor,
                                       nativeFactors: [1] + switches)
    }

    private func observeZoom(on device: AVCaptureDevice) {
        zoomObservations = [
            device.observe(\.videoZoomFactor, options: [.new]) { [weak self] _, _ in self?.scheduleZoomRefresh() },
            device.observe(\.minAvailableVideoZoomFactor, options: [.new]) { [weak self] _, _ in self?.scheduleZoomRefresh() },
            device.observe(\.maxAvailableVideoZoomFactor, options: [.new]) { [weak self] _, _ in self?.scheduleZoomRefresh() },
        ]
        if #available(iOS 18.0, *) {
            zoomObservations.append(device.observe(\.displayVideoZoomFactorMultiplier, options: [.new]) { [weak self] _, _ in
                self?.scheduleZoomRefresh()
            })
        }
        publishZoomState()
    }

    private func scheduleZoomRefresh() {
        sessionQueue.async { [weak self] in self?.publishZoomState() }
    }

    private func publishZoomState() {
        guard let device = captureDevice else { return }
        let configuration = zoomConfiguration(for: device)
        let bounded = configuration.clampedDeviceFactor(device.videoZoomFactor)
        if !zoomLocked, abs(bounded - device.videoZoomFactor) > 0.001 {
            do {
                try device.lockForConfiguration()
                device.cancelVideoZoomRamp()
                device.videoZoomFactor = bounded
                device.unlockForConfiguration()
            } catch { reportZoomError() }
        }
        let actual = device.videoZoomFactor
        DispatchQueue.main.async { [weak self] in self?.renderZoom(configuration: configuration, factor: actual) }
    }

    @objc private func pinchZoom(_ gesture: UIPinchGestureRecognizer) {
        guard cameraIsReady, !captureState.isBusy else { return }
        let state = gesture.state
        let scale = gesture.scale
        sessionQueue.async { [weak self] in
            guard let self, !self.zoomLocked, let device = self.captureDevice else { return }
            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }
                if state == .began {
                    device.cancelVideoZoomRamp()
                    self.pinchStartFactor = device.videoZoomFactor
                } else if state == .changed || state == .ended {
                    if let start = self.pinchStartFactor {
                        device.videoZoomFactor = self.zoomConfiguration(for: device).clampedDeviceFactor(start * scale)
                    }
                }
                if state == .ended || state == .cancelled || state == .failed { self.pinchStartFactor = nil }
            } catch { self.pinchStartFactor = nil; self.reportZoomError() }
            self.publishZoomState()
        }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        var touchedView = touch.view
        while let current = touchedView {
            if current is UIControl || current === zoomPanel { return false }
            touchedView = current.superview
        }
        return true
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard cameraIsReady, !captureState.isBusy, let previewLayer, let rect = previewVideoRect() else { return false }
        if gestureRecognizer is UIPinchGestureRecognizer {
            guard gestureRecognizer.numberOfTouches >= 2 else { return false }
            for index in 0..<gestureRecognizer.numberOfTouches {
                let point = gestureRecognizer.location(ofTouch: index, in: view)
                if !rect.contains(previewLayer.convert(point, from: view.layer)) { return false }
            }
            return true
        }
        return rect.contains(previewLayer.convert(gestureRecognizer.location(in: view), from: view.layer))
    }

    private func reportZoomError() {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.viewIfLoaded?.window != nil, self.presentedViewController == nil,
                  !self.captureState.isBusy else { return }
            let alert = UIAlertController(title: "无法调整镜头倍率", message: "已保留当前倍率，请重试。", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "知道了", style: .default))
            self.present(alert, animated: true)
        }
    }

    private func captureFailed(message: String) {
        captureState.fail()
        sessionQueue.async { [weak self] in self?.zoomLocked = false }
        libraryButton.isEnabled = true
        shutter.isEnabled = cameraIsReady
        shutter.alpha = shutter.isEnabled ? 1 : 0.62
        updateZoomAvailability()
        let alert = UIAlertController(title: "拍照失败", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "知道了", style: .default))
        present(alert, animated: true)
    }

    private func capture() {
        guard !captureState.isBusy else { return }
        guard session.isRunning else {
            cameraStatusView.isHidden = false
            cameraStatusLabel.text = "镜头还在准备，请稍等一下"
            configureAndStartSession()
            return
        }
        guard captureState.begin() else { return }
        libraryButton.isEnabled = false
        shutter.isEnabled = false
        shutter.alpha = 0.6
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        updateZoomAvailability()
        let mirrored = previewLayer?.connection?.isVideoMirrored == true
        let selectedFlash = flashMode
        sessionQueue.async { [weak self] in
            guard let self, let device = self.captureDevice else { return }
            self.zoomLocked = true
            self.pinchStartFactor = nil
            do {
                try device.lockForConfiguration()
                device.cancelVideoZoomRamp()
                device.unlockForConfiguration()
            } catch {
                DispatchQueue.main.async { self.captureFailed(message: "无法固定镜头倍率，请再拍一次。") }
                return
            }
            if let connection = self.output.connection(with: .video), connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = mirrored
            }
            let settings = AVCapturePhotoSettings()
            if self.output.supportedFlashModes.contains(selectedFlash) {
                settings.flashMode = selectedFlash
            }
            self.output.capturePhoto(with: settings, delegate: self)
        }
    }

    private func toggleFlash() {
        guard !captureState.isBusy else { return }
        flashMode = flashMode == .off ? .auto : .off
        headerState.flashAutomatic = flashMode == .auto
    }

    @objc private func focus(at recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended,
              let previewLayer,
              let device = captureDevice else { return }
        let point = recognizer.location(in: view)
        let layerPoint = previewLayer.convert(point, from: view.layer)
        guard let videoRect = previewVideoRect(), videoRect.contains(layerPoint) else { return }
        let devicePoint = previewLayer.captureDevicePointConverted(fromLayerPoint: layerPoint)
        guard cameraIsReady, !captureState.isBusy else { return }
        guideView.showFocus(at: guideView.convert(point, from: view))
        sessionQueue.async { [weak self] in
            guard let self, !self.zoomLocked else { return }
            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }
                if device.isFocusPointOfInterestSupported, device.isFocusModeSupported(.autoFocus) {
                    device.focusPointOfInterest = devicePoint
                    device.focusMode = .autoFocus
                }
                if device.isExposurePointOfInterestSupported, device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposurePointOfInterest = devicePoint
                    device.exposureMode = .continuousAutoExposure
                }
            } catch {}
        }
    }

    @objc private func edgeSwipeBack(_ recognizer: UIScreenEdgePanGestureRecognizer) {
        guard recognizer.state == .ended,
              recognizer.translation(in: view).x > 72 else { return }
        onCancel?()
    }

    private func glassPanel(cornerRadius: CGFloat) -> UIVisualEffectView {
        let glass = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialLight))
        glass.translatesAutoresizingMaskIntoConstraints = false
        glass.layer.cornerRadius = cornerRadius
        glass.layer.cornerCurve = .continuous
        glass.clipsToBounds = true
        glass.layer.borderWidth = 1
        glass.layer.borderColor = UIColor(Color.pencil).withAlphaComponent(0.18).cgColor
        return glass
    }

    private func showPermissionError() {
        showCameraStatus(
            message: "相机权限尚未开启\n你仍然可以从相册选择照片。",
            symbol: "camera.fill.badge.ellipsis",
            action: .settings
        )
    }

    private func showCameraUnavailable() {
        showCameraStatus(
            message: "当前设备没有可用镜头\n可以从右下角选择一张照片。",
            symbol: "camera.slash.fill"
        )
    }

    private func showCameraRunning() {
        updateGuideFrame()
        cameraStatusPanel?.isHidden = true
        cameraIsReady = true
        updateZoomAvailability()
        shutter.isEnabled = !captureState.isBusy
        shutter.alpha = shutter.isEnabled ? 1 : 0.62
    }

    private func startPreviewReadinessCheck() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.startPreviewReadinessCheck() }
            return
        }

        let token = UUID()
        previewCheckToken = token
        checkPreviewReadiness(token: token, attempt: 0)
    }

    private func checkPreviewReadiness(token: UUID, attempt: Int) {
        guard token == previewCheckToken else { return }
        guard session.isRunning else {
            showCameraStatus(message: "镜头还没有启动，请重试。", symbol: "exclamationmark.camera.fill", action: .retry)
            return
        }

        let isReady = hasReceivedFirstVideoFrame && previewLayer?.connection?.isEnabled == true
        if isReady {
            showCameraRunning()
            return
        }

        if attempt < 20 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.checkPreviewReadiness(token: token, attempt: attempt + 1)
            }
        } else {
            showCameraStatus(
                message: "相机已授权，但预览画面还没有准备好。\n请点击重试。",
                symbol: "exclamationmark.camera.fill",
                action: .retry
            )
        }
    }

    private func showCameraStatus(
        message: String,
        symbol: String,
        action: CameraStatusAction = .none
    ) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.showCameraStatus(message: message, symbol: symbol, action: action)
            }
            return
        }
        cameraIsReady = false
        updateZoomAvailability()
        cameraStatusPanel?.isHidden = false
        cameraStatusLabel.text = message
        cameraStatusIcon.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 32, weight: .bold))
        cameraStatusAction = action
        cameraStatusActionButton.isHidden = action == .none
        var actionConfiguration = cameraStatusActionButton.configuration
        actionConfiguration?.title = action == .settings ? "前往设置" : "重新连接"
        cameraStatusActionButton.configuration = actionConfiguration
        shutter.isEnabled = false
        shutter.alpha = 0.62
    }

    private func performCameraStatusAction() {
        switch cameraStatusAction {
        case .none:
            break
        case .retry:
            configureAndStartSession()
        case .settings:
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
            UIApplication.shared.open(url)
        }
    }

    private func presentPhotoPicker() {
        guard captureState.begin() else { return }
        updateZoomAvailability()
        sessionQueue.async { [weak self] in
            guard let self, let device = self.captureDevice else { return }
            self.zoomLocked = true
            self.pinchStartFactor = nil
            if (try? device.lockForConfiguration()) != nil {
                device.cancelVideoZoomRamp()
                device.unlockForConfiguration()
            }
        }
        stopSession()
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = 1
        configuration.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        picker.modalPresentationStyle = .fullScreen
        present(picker, animated: true)
    }

    @objc private func sessionRuntimeError(_ notification: Notification) {
        guard isSessionConfigured else {
            showCameraUnavailable()
            return
        }
        if let error = notification.userInfo?[AVCaptureSessionErrorKey] as? NSError,
           error.domain == AVFoundationErrorDomain,
           error.code == AVError.mediaServicesWereReset.rawValue {
            configureAndStartSession()
            return
        }
        showCameraStatus(
            message: "相机连接中断，请重新连接。",
            symbol: "exclamationmark.camera.fill",
            action: .retry
        )
    }

    @objc private func sessionWasInterrupted(_ notification: Notification) {
        let reason = (notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as? NSNumber)
            .flatMap { AVCaptureSession.InterruptionReason(rawValue: $0.intValue) }
        let message: String
        switch reason {
        case .videoDeviceInUseByAnotherClient, .audioDeviceInUseByAnotherClient:
            message = "相机暂时被其他应用占用。"
        case .videoDeviceNotAvailableInBackground:
            message = "相机将在回到前台后继续连接。"
        case .videoDeviceNotAvailableWithMultipleForegroundApps:
            message = "当前系统状态暂时无法使用相机。"
        default:
            message = "相机暂时中断，请稍候或重试。"
        }
        showCameraStatus(message: message, symbol: "pause.circle.fill", action: .retry)
    }

    @objc private func sessionInterruptionEnded(_ notification: Notification) {
        configureAndStartSession()
    }

    @objc private func applicationDidBecomeActive() {
        guard viewIfLoaded?.window != nil, presentedViewController == nil else { return }
        authorizeAndStartCamera()
    }
}

extension CameraViewController: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        guard error != nil else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.captureState.isBusy, !self.captureState.didDeliver else { return }
            self.captureFailed(message: "镜头拍摄失败，请再拍一次。")
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil,
              let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else {
            DispatchQueue.main.async { [weak self] in
                self?.captureFailed(message: "无法读取照片，请再拍一次。")
            }
            return
        }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.captureState.finish() else { return }
            self.stopSession()
            self.onImage?(CapturedPhoto(image: image,
                                       sourceFrame: self.previewVideoRect().map {
                                           self.view.convert(self.view.layer.convert($0, from: self.previewLayer!), to: nil)
                                       }))
        }
    }
}

extension CameraViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.hasReceivedFirstVideoFrame else { return }
            self.hasReceivedFirstVideoFrame = true
        }
    }
}

extension CameraViewController: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        guard let provider = results.first?.itemProvider else {
            captureState.fail()
            picker.dismiss(animated: true) { [weak self] in self?.authorizeAndStartCamera() }
            return
        }

        guard provider.canLoadObject(ofClass: UIImage.self) else {
            captureState.fail()
            picker.dismiss(animated: true) { [weak self] in
                self?.showCameraStatus(
                    message: "无法读取这张照片，请重新选择。",
                    symbol: "photo.badge.exclamationmark"
                )
            }
            return
        }

        provider.loadObject(ofClass: UIImage.self) { [weak self, weak picker] object, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                guard let image = object as? UIImage else {
                    self.captureState.fail()
                    picker?.dismiss(animated: true) {
                        self.showCameraStatus(
                            message: "无法读取这张照片，请重新选择。",
                            symbol: "photo.badge.exclamationmark"
                        )
                    }
                    return
                }
                picker?.dismiss(animated: true) {
                    guard self.captureState.finish() else { return }
                    self.onImage?(CapturedPhoto(image: image, sourceFrame: nil))
                }
            }
        }
    }
}

private final class CameraGuideView: UIView {
    var isGridVisible = false { didSet { updateGuidePath() } }
    private var focusPoint: CGPoint? { didSet { updateGuidePath() } }
    private let cornerInkLayer = CAShapeLayer()
    private let cornerYellowLayer = CAShapeLayer()
    private let gridLayer = CAShapeLayer()
    private let focusInkLayer = CAShapeLayer()
    private let focusYellowLayer = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        isUserInteractionEnabled = false
        clipsToBounds = true
        for shape in [gridLayer, cornerInkLayer, cornerYellowLayer, focusInkLayer, focusYellowLayer] {
            shape.fillColor = UIColor.clear.cgColor
            shape.lineCap = .round
            shape.lineJoin = .round
            layer.addSublayer(shape)
        }
        cornerInkLayer.strokeColor = UIColor(Color.recognitionInk).cgColor
        cornerYellowLayer.strokeColor = UIColor(Color.recognitionYellow).cgColor
        gridLayer.strokeColor = UIColor.white.withAlphaComponent(0.35).cgColor
        gridLayer.lineWidth = 1
        focusInkLayer.strokeColor = UIColor(Color.recognitionInk).cgColor
        focusInkLayer.lineWidth = 4
        focusYellowLayer.strokeColor = UIColor(Color.recognitionYellow).cgColor
        focusYellowLayer.lineWidth = 2.5
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        for shape in [gridLayer, cornerInkLayer, cornerYellowLayer, focusInkLayer, focusYellowLayer] {
            shape.frame = bounds
        }
        updateGuidePath()
    }

    private func updateGuidePath() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let guide = bounds.insetBy(dx: 24, dy: 28)
        let scale = RecognitionRangeGeometry.strokeScale(in: guide, scale: bounds.width / 540)
        // Reuse the exact rounded corner geometry and two-color stroke of object boxes.
        let corners = RecognitionRangeGeometry.path(in: guide, scale: scale).cgPath
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        cornerInkLayer.path = corners
        cornerInkLayer.lineWidth = 4 * scale
        cornerYellowLayer.path = corners
        cornerYellowLayer.lineWidth = 2.5 * scale

        let grid = UIBezierPath()
        if isGridVisible {
            for fraction in [CGFloat(1.0 / 3.0), CGFloat(2.0 / 3.0)] {
                grid.move(to: CGPoint(x: guide.minX + guide.width * fraction, y: guide.minY))
                grid.addLine(to: CGPoint(x: guide.minX + guide.width * fraction, y: guide.maxY))
                grid.move(to: CGPoint(x: guide.minX, y: guide.minY + guide.height * fraction))
                grid.addLine(to: CGPoint(x: guide.maxX, y: guide.minY + guide.height * fraction))
            }
        }
        gridLayer.path = grid.cgPath
        let focus = focusPoint.map {
            UIBezierPath(ovalIn: CGRect(x: $0.x - 32, y: $0.y - 32, width: 64, height: 64)).cgPath
        }
        focusInkLayer.path = focus
        focusYellowLayer.path = focus
        CATransaction.commit()
    }

    func showFocus(at point: CGPoint) {
        focusPoint = point
        UIView.animate(withDuration: 0.18, animations: {
            self.transform = CGAffineTransform(scaleX: 0.985, y: 0.985)
        }) { _ in
            UIView.animate(withDuration: 0.18) { self.transform = .identity }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { [weak self] in
            self?.focusPoint = nil
        }
    }
}

struct CapturedPhoto {
    let image: UIImage
    /// Frame in window coordinates; nil for library imports.
    let sourceFrame: CGRect?
}

struct CameraCaptureState {
    private(set) var isBusy = false
    private(set) var didDeliver = false

    mutating func begin() -> Bool {
        guard !isBusy, !didDeliver else { return false }
        isBusy = true
        return true
    }

    mutating func fail() {
        guard !didDeliver else { return }
        isBusy = false
    }

    mutating func finish() -> Bool {
        guard isBusy, !didDeliver else { return false }
        didDeliver = true
        return true
    }
}

/// Measures the displayed photo in UIWindow coordinates, matching the camera callback.
struct CapturePhotoFrameReader: UIViewRepresentable {
    let onFrame: (CGRect) -> Void

    func makeUIView(context: Context) -> CapturePhotoFrameReportingView {
        let view = CapturePhotoFrameReportingView()
        view.onFrame = onFrame
        return view
    }

    func updateUIView(_ view: CapturePhotoFrameReportingView, context: Context) {
        view.onFrame = onFrame
        view.setNeedsLayout()
    }
}

final class CapturePhotoFrameReportingView: UIView {
    var onFrame: ((CGRect) -> Void)?
    private var lastFrame = CGRect.zero

    override func didMoveToWindow() {
        super.didMoveToWindow()
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Read after the surrounding SwiftUI/NavigationStack layout has settled.
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window, self.bounds.width > 0,
                  self.bounds.height > 0 else { return }
            let frame = self.convert(self.bounds, to: window)
            guard frame != self.lastFrame else { return }
            self.lastFrame = frame
            self.onFrame?(frame)
        }
    }
}

/// Keeps the camera and recognition inside one presentation and owns the photo handoff.
struct CaptureRecognitionFlowView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var photo: CapturedPhoto?
    @State private var targetPhotoFrame = CGRect.zero
    @State private var isAnimating = false
    @State private var didTransition = false
    @State private var resultVisible = false

    var body: some View {
        ZStack {
            NotebookBackground()
            if let photo {
                NavigationStack {
                    RecognitionFlowView(image: photo.image,
                                        revealsAnnotations: didTransition,
                                        onPhotoFrameChange: transition)
                        .toolbar(.hidden, for: .navigationBar)
                }
                .opacity(resultVisible ? 1 : 0)
                .allowsHitTesting(didTransition)
                .accessibilityHidden(!didTransition)
            }
            if !didTransition {
                CameraView { captured in
                    guard photo == nil else { return }
                    photo = captured
                } onCancel: {
                    guard photo == nil else { return }
                    dismiss()
                }
                .ignoresSafeArea()
                .opacity(resultVisible ? 0 : 1)
                .allowsHitTesting(photo == nil)
                .accessibilityHidden(photo != nil)
            }
            if let photo, let source = photo.sourceFrame, !didTransition {
                CapturePhotoTransitionOverlay(
                    image: photo.image,
                    source: source,
                    target: targetPhotoFrame.width > 0 ? targetPhotoFrame : nil,
                    reduceMotion: reduceMotion,
                    onComplete: { didTransition = true }
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
        .task(id: isAnimating) {
            guard isAnimating, photo?.sourceFrame == nil else { return }
            do {
                try await Task.sleep(for: .seconds(reduceMotion ? 0.15 : 0.35))
            } catch { return }
            didTransition = true
        }
    }

    private func transition(to target: CGRect) {
        guard photo != nil, !isAnimating, !didTransition else { return }
        // Defer the handoff so the frozen source photo is rendered first.
        DispatchQueue.main.async {
            guard !isAnimating, !didTransition else { return }
            targetPhotoFrame = target
            isAnimating = true
            withAnimation(.easeInOut(duration: reduceMotion ? 0.15 : 0.35)) {
                resultVisible = true
            }
        }
    }
}


private struct CapturePhotoTransitionOverlay: UIViewRepresentable {
    let image: UIImage
    let source: CGRect
    let target: CGRect?
    let reduceMotion: Bool
    let onComplete: () -> Void

    func makeUIView(context: Context) -> CapturePhotoTransitionOverlayView {
        let view = CapturePhotoTransitionOverlayView()
        view.imageView.image = image
        return view
    }

    func updateUIView(_ view: CapturePhotoTransitionOverlayView, context: Context) {
        view.source = source
        view.target = target
        view.reduceMotion = reduceMotion
        view.onComplete = onComplete
        view.setNeedsLayout()
    }
}

/// Both endpoints are measured in the same UIWindow. Convert them into this view
/// before animating the actual image frame; completion hands off at the exact endpoint.
final class CapturePhotoTransitionOverlayView: UIView {
    let imageView = UIImageView()
    var source = CGRect.zero
    var target: CGRect?
    var reduceMotion = false
    var duration: TimeInterval = 0.35
    var onComplete: (() -> Void)?
    private var didStart = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 22
        imageView.layer.cornerCurve = .continuous
        addSubview(imageView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard !didStart, let window, bounds.width > 0, bounds.height > 0,
              source.width > 0 else { return }
        imageView.frame = convert(source, from: window)
        guard let target, target.width > 0, target.height > 0 else { return }
        didStart = true
        let destination = convert(target, from: window)
        DispatchQueue.main.async { [weak self] in
            guard let self, self.window != nil else { return }
            UIView.animate(withDuration: self.reduceMotion ? 0.15 : self.duration,
                           delay: 0, options: [.curveEaseInOut]) {
                if self.reduceMotion {
                    self.imageView.alpha = 0
                } else {
                    self.imageView.frame = destination
                }
            } completion: { [weak self] _ in
                guard let self else { return }
                // Interrupted animations must also finish at the result photo's bounds.
                if !self.reduceMotion { self.imageView.frame = destination }
                self.onComplete?()
            }
        }
    }
}


struct CameraZoomConfiguration {
    let multiplier: CGFloat
    let minimum: CGFloat
    let maximum: CGFloat
    let presets: [CGFloat]

    init(multiplier: CGFloat, minimum: CGFloat, maximum: CGFloat, nativeFactors: [CGFloat]) {
        let normalization = multiplier.isFinite && multiplier > 0 ? multiplier : 1
        self.multiplier = normalization
        self.minimum = max(minimum, 1)
        self.maximum = max(self.minimum, min(maximum, 10 / normalization))
        let lower = self.minimum * normalization
        let upper = self.maximum * normalization
        let candidates = ([CGFloat(1), 2] + nativeFactors.map { $0 * normalization }).sorted()
        var available: [CGFloat] = []
        for candidate in candidates where candidate.isFinite && candidate >= lower - 0.001 && candidate <= upper + 0.001 {
            if available.last.map({ abs($0 - candidate) > 0.05 }) ?? true { available.append(candidate) }
        }
        presets = available
    }

    static func legacyMultiplier(wideIndex: Int, switchFactors: [CGFloat]) -> CGFloat {
        guard wideIndex > 0, wideIndex <= switchFactors.count,
              switchFactors[wideIndex - 1] > 0 else { return 1 }
        return 1 / switchFactors[wideIndex - 1]
    }

    func clampedDeviceFactor(_ factor: CGFloat) -> CGFloat {
        guard factor.isFinite else { return minimum }
        return min(max(factor, minimum), maximum)
    }

    func deviceFactor(for display: CGFloat) -> CGFloat {
        clampedDeviceFactor(display / multiplier)
    }

    func displayFactor(for device: CGFloat) -> CGFloat {
        device * multiplier
    }

    static func label(for factor: CGFloat) -> String {
        let rounded = (factor * 10).rounded() / 10
        return rounded == rounded.rounded()
            ? String(format: "%.0f×", Double(rounded))
            : String(format: "%.1f×", Double(rounded))
    }
}


private final class CameraHeaderState: ObservableObject {
    @Published var flashEnabled = false
    @Published var flashAutomatic = false
}

private struct CameraPageHeader: View {
    @ObservedObject var state: CameraHeaderState
    let onClose: () -> Void
    let onFlash: () -> Void

    var body: some View {
        PictureWordPageHeader(
            eyebrow: "CAMERA", title: "拍照学单词",
            foreground: .ink, eyebrowColor: .ink.opacity(0.55), tint: .paperLight.opacity(0.8)
        ) {
            PictureWordHeaderCapsule(tint: .paperLight.opacity(0.8), foreground: .ink, interactive: true) {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .bold))
                        .frame(width: 50, height: 50)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭相机")
            }
        } trailing: {
            PictureWordHeaderCapsule(tint: .paperLight.opacity(0.8), foreground: .ink, interactive: true) {
                Button(action: onFlash) {
                    Image(systemName: state.flashAutomatic ? "bolt.badge.automatic.fill" : "bolt.slash.fill")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(state.flashAutomatic ? Color.sun : Color.ink)
                        .frame(width: 50, height: 50)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!state.flashEnabled)
                .opacity(state.flashEnabled ? 1 : 0.45)
                .accessibilityLabel(state.flashAutomatic ? "闪光灯自动" : "闪光灯已关闭")
            }
        }
    }
}
