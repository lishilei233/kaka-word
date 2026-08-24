import AVFoundation
import PhotosUI
import SwiftUI

/// 将基于 AVFoundation 的相机控制器桥接到 SwiftUI。
struct CameraView: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> CameraViewController {
        let controller = CameraViewController()
        controller.onImage = onImage
        controller.onCancel = onCancel
        return controller
    }

    func updateUIViewController(_ uiViewController: CameraViewController, context: Context) {}
}

final class CameraViewController: UIViewController {
    var onImage: ((UIImage) -> Void)?
    var onCancel: (() -> Void)?

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.pictureword.camera.session", qos: .userInitiated)
    private let output = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let videoFrameQueue = DispatchQueue(label: "com.pictureword.camera.video-frame", qos: .userInitiated)
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var captureDevice: AVCaptureDevice?
    private var isSessionConfigured = false
    private var cameraPosition: AVCaptureDevice.Position = .back
    private var previewCheckToken = UUID()
    private var hasReceivedFirstVideoFrame = false
    private let guideView = CameraGuideView()
    private let shutter = UIButton(type: .custom)
    private let flashButton = UIButton(type: .system)
    private let cameraSwitchButton = UIButton(type: .system)
    private let libraryButton = UIButton(type: .system)
    private let cameraStatusView = UIStackView()
    private let cameraStatusIcon = UIImageView()
    private let cameraStatusLabel = UILabel()
    private let cameraStatusActionButton = UIButton(type: .system)
    private var cameraStatusPanel: UIVisualEffectView?
    private var cameraStatusAction: CameraStatusAction = .none
    private var flashMode: AVCaptureDevice.FlashMode = .off

    private enum CameraStatusAction {
        case none
        case retry
        case settings
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.141, green: 0.129, blue: 0.118, alpha: 1)
        installPreviewLayer()
        addControls()
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
        previewLayer?.frame = view.bounds
        if let connection = previewLayer?.connection {
            if connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
        }
        guideView.frame = view.bounds
        guideView.setNeedsLayout()
    }

    private func installPreviewLayer() {
        let layer = AVCaptureVideoPreviewLayer(session: session)
        // 完整展示 4:3 传感器画面，避免全屏 aspectFill 裁掉左右两侧而产生“2× 变焦”错觉。
        layer.videoGravity = .resizeAspect
        layer.backgroundColor = UIColor.clear.cgColor
        layer.frame = view.bounds
        previewLayer = layer
        view.layer.insertSublayer(layer, at: 0)
    }

    private func addCameraStatus() {
        cameraStatusIcon.image = UIImage(systemName: "camera.aperture", withConfiguration: UIImage.SymbolConfiguration(pointSize: 32, weight: .bold))
        cameraStatusIcon.tintColor = UIColor(red: 0.96, green: 0.79, blue: 0.37, alpha: 1)

        cameraStatusLabel.text = "正在启动相机…"
        cameraStatusLabel.textColor = UIColor.white.withAlphaComponent(0.72)
        cameraStatusLabel.font = .systemFont(ofSize: 15, weight: .bold)
        cameraStatusLabel.numberOfLines = 0
        cameraStatusLabel.textAlignment = .center

        var actionConfiguration = UIButton.Configuration.filled()
        actionConfiguration.baseForegroundColor = .white
        actionConfiguration.baseBackgroundColor = UIColor(red: 0.95, green: 0.43, blue: 0.38, alpha: 1)
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

                guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: self.cameraPosition),
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
            }

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
        guideView.translatesAutoresizingMaskIntoConstraints = false
        guideView.isUserInteractionEnabled = false
        view.addSubview(guideView)

        let close = UIButton(type: .system)
        close.setImage(UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(weight: .bold)), for: .normal)
        close.tintColor = .white
        close.addAction(UIAction { [weak self] _ in self?.onCancel?() }, for: .touchUpInside)
        let closeGlass = glassControl(containing: close)

        let eyebrow = UILabel()
        eyebrow.text = "PICTURE WORD"
        eyebrow.textColor = UIColor(red: 0.96, green: 0.79, blue: 0.37, alpha: 1)
        eyebrow.font = .systemFont(ofSize: 10, weight: .black)
        eyebrow.textAlignment = .center

        let title = UILabel()
        title.text = "把生活装进单词册"
        title.textColor = .white
        title.font = .systemFont(ofSize: 15, weight: .bold)
        title.textAlignment = .center

        let titleStack = UIStackView(arrangedSubviews: [eyebrow, title])
        titleStack.axis = .vertical
        titleStack.spacing = 2
        titleStack.alignment = .fill
        titleStack.translatesAutoresizingMaskIntoConstraints = false
        let titleGlass = glassPanel(cornerRadius: 25)
        titleGlass.contentView.addSubview(titleStack)
        NSLayoutConstraint.activate([
            titleStack.leadingAnchor.constraint(equalTo: titleGlass.contentView.leadingAnchor, constant: 18),
            titleStack.trailingAnchor.constraint(equalTo: titleGlass.contentView.trailingAnchor, constant: -18),
            titleStack.centerYAnchor.constraint(equalTo: titleGlass.contentView.centerYAnchor),
            titleGlass.heightAnchor.constraint(equalToConstant: 50),
        ])

        flashButton.setImage(UIImage(systemName: "bolt.slash.fill", withConfiguration: UIImage.SymbolConfiguration(weight: .bold)), for: .normal)
        flashButton.tintColor = .white
        flashButton.addAction(UIAction { [weak self] _ in self?.toggleFlash() }, for: .touchUpInside)
        let flashGlass = glassControl(containing: flashButton)

        cameraSwitchButton.setImage(UIImage(systemName: "arrow.triangle.2.circlepath.camera", withConfiguration: UIImage.SymbolConfiguration(weight: .bold)), for: .normal)
        cameraSwitchButton.tintColor = .white
        cameraSwitchButton.accessibilityLabel = "切换前后摄像头"
        cameraSwitchButton.addAction(UIAction { [weak self] _ in self?.switchCamera() }, for: .touchUpInside)
        cameraSwitchButton.isEnabled = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) != nil
        cameraSwitchButton.alpha = cameraSwitchButton.isEnabled ? 1 : 0.45
        let cameraSwitchGlass = glassControl(containing: cameraSwitchButton)

        let topBar = UIStackView(arrangedSubviews: [closeGlass, titleGlass, cameraSwitchGlass, flashGlass])
        topBar.axis = .horizontal
        topBar.alignment = .center
        topBar.spacing = 6
        topBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(topBar)

        let hintIcon = UIImageView(image: UIImage(systemName: "viewfinder", withConfiguration: UIImage.SymbolConfiguration(weight: .bold)))
        hintIcon.tintColor = .white
        let hintLabel = UILabel()
        hintLabel.text = "让物品留在取景框里"
        hintLabel.textColor = .white
        hintLabel.font = .systemFont(ofSize: 13, weight: .semibold)
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
        gridButton.tintColor = .white
        gridButton.addAction(UIAction { [weak self, weak gridButton] _ in
            guard let self else { return }
            self.guideView.isGridVisible.toggle()
            gridButton?.tintColor = self.guideView.isGridVisible
                ? UIColor(red: 0.96, green: 0.79, blue: 0.37, alpha: 1)
                : .white
        }, for: .touchUpInside)
        gridButton.widthAnchor.constraint(equalToConstant: 50).isActive = true
        gridButton.heightAnchor.constraint(equalToConstant: 50).isActive = true

        shutter.backgroundColor = UIColor(red: 0.96, green: 0.79, blue: 0.37, alpha: 1)
        shutter.layer.cornerRadius = 38
        shutter.layer.borderWidth = 5
        shutter.layer.borderColor = UIColor.white.withAlphaComponent(0.9).cgColor
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
        libraryConfiguration.title = "相册"
        libraryConfiguration.imagePlacement = .top
        libraryConfiguration.imagePadding = 4
        libraryConfiguration.baseForegroundColor = .white
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
        let bottomGlass = glassPanel(cornerRadius: 42)
        bottomGlass.contentView.addSubview(bottomStack)
        view.addSubview(bottomGlass)

        let focusTap = UITapGestureRecognizer(target: self, action: #selector(focus(at:)))
        focusTap.cancelsTouchesInView = false
        view.addGestureRecognizer(focusTap)

        let backSwipe = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(edgeSwipeBack(_:)))
        backSwipe.edges = .left
        view.addGestureRecognizer(backSwipe)

        NSLayoutConstraint.activate([
            guideView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            guideView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            guideView.topAnchor.constraint(equalTo: view.topAnchor),
            guideView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            closeGlass.widthAnchor.constraint(equalToConstant: 50),
            closeGlass.heightAnchor.constraint(equalToConstant: 50),
            cameraSwitchGlass.widthAnchor.constraint(equalToConstant: 50),
            cameraSwitchGlass.heightAnchor.constraint(equalToConstant: 50),
            flashGlass.widthAnchor.constraint(equalToConstant: 50),
            flashGlass.heightAnchor.constraint(equalToConstant: 50),
            topBar.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 18),
            topBar.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -18),
            topBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),

            hintGlass.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            hintGlass.bottomAnchor.constraint(equalTo: bottomGlass.topAnchor, constant: -14),

            bottomGlass.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            bottomGlass.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            bottomGlass.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
            bottomGlass.heightAnchor.constraint(equalToConstant: 102),
            bottomStack.leadingAnchor.constraint(equalTo: bottomGlass.contentView.leadingAnchor, constant: 24),
            bottomStack.trailingAnchor.constraint(equalTo: bottomGlass.contentView.trailingAnchor, constant: -24),
            bottomStack.centerYAnchor.constraint(equalTo: bottomGlass.contentView.centerYAnchor),
            shutter.widthAnchor.constraint(equalToConstant: 76),
            shutter.heightAnchor.constraint(equalToConstant: 76),
        ])
    }

    private func capture() {
        guard session.isRunning else {
            cameraStatusView.isHidden = false
            cameraStatusLabel.text = "镜头还在准备，请稍等一下"
            configureAndStartSession()
            return
        }
        shutter.isEnabled = false
        shutter.alpha = 0.6
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        if let photoConnection = output.connection(with: .video),
           photoConnection.isVideoMirroringSupported {
            photoConnection.automaticallyAdjustsVideoMirroring = false
            photoConnection.isVideoMirrored = previewLayer?.connection?.isVideoMirrored == true
        }
        let settings = AVCapturePhotoSettings()
        if captureDevice?.hasFlash == true {
            settings.flashMode = flashMode
        }
        output.capturePhoto(with: settings, delegate: self)
    }

    private func toggleFlash() {
        flashMode = flashMode == .off ? .auto : .off
        let name = flashMode == .off ? "bolt.slash.fill" : "bolt.badge.automatic.fill"
        flashButton.setImage(UIImage(systemName: name, withConfiguration: UIImage.SymbolConfiguration(weight: .bold)), for: .normal)
        flashButton.tintColor = flashMode == .off
            ? .white
            : UIColor(red: 0.96, green: 0.79, blue: 0.37, alpha: 1)
        flashButton.accessibilityLabel = flashMode == .off ? "闪光灯已关闭" : "闪光灯自动"
    }

    private func switchCamera() {
        let nextPosition: AVCaptureDevice.Position = cameraPosition == .back ? .front : .back
        showCameraStatus(message: "正在切换镜头…", symbol: "arrow.triangle.2.circlepath.camera")
        hasReceivedFirstVideoFrame = false
        sessionQueue.async { [weak self] in
            guard let self,
                  let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: nextPosition),
                  let newInput = try? AVCaptureDeviceInput(device: device) else {
                DispatchQueue.main.async { [weak self] in
                    self?.showCameraStatus(
                        message: "没有找到可用的前置或后置镜头。",
                        symbol: "camera.slash.fill",
                        action: .retry
                    )
                }
                return
            }

            let oldInput = self.session.inputs.compactMap { $0 as? AVCaptureDeviceInput }.first
            self.session.beginConfiguration()
            if let oldInput {
                self.session.removeInput(oldInput)
            }

            guard self.session.canAddInput(newInput) else {
                if let oldInput, self.session.canAddInput(oldInput) {
                    self.session.addInput(oldInput)
                }
                self.session.commitConfiguration()
                DispatchQueue.main.async { [weak self] in
                    self?.showCameraStatus(
                        message: "镜头切换失败，请重试。",
                        symbol: "exclamationmark.camera.fill",
                        action: .retry
                    )
                }
                return
            }

            self.session.addInput(newInput)
            self.session.commitConfiguration()
            self.captureDevice = device
            self.cameraPosition = nextPosition
            if !self.session.isRunning {
                self.session.startRunning()
            }
            DispatchQueue.main.async { [weak self] in
                self?.startPreviewReadinessCheck()
            }
        }
    }

    @objc private func focus(at recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended,
              let previewLayer,
              let device = captureDevice else { return }
        let point = recognizer.location(in: view)
        guard point.y > view.safeAreaInsets.top + 82,
              point.y < view.bounds.height - view.safeAreaInsets.bottom - 150 else { return }
        let devicePoint = previewLayer.captureDevicePointConverted(fromLayerPoint: point)
        do {
            try device.lockForConfiguration()
            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = devicePoint
                device.focusMode = .autoFocus
            }
            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = devicePoint
                device.exposureMode = .continuousAutoExposure
            }
            device.unlockForConfiguration()
            guideView.showFocus(at: point)
        } catch {}
    }

    @objc private func edgeSwipeBack(_ recognizer: UIScreenEdgePanGestureRecognizer) {
        guard recognizer.state == .ended,
              recognizer.translation(in: view).x > 72 else { return }
        onCancel?()
    }

    private func glassPanel(cornerRadius: CGFloat) -> UIVisualEffectView {
        let glass = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
        glass.translatesAutoresizingMaskIntoConstraints = false
        glass.layer.cornerRadius = cornerRadius
        glass.layer.cornerCurve = .continuous
        glass.clipsToBounds = true
        glass.layer.borderWidth = 1
        glass.layer.borderColor = UIColor.white.withAlphaComponent(0.26).cgColor
        return glass
    }

    private func glassControl(containing button: UIButton) -> UIVisualEffectView {
        let glass = glassPanel(cornerRadius: 25)
        button.translatesAutoresizingMaskIntoConstraints = false
        glass.contentView.addSubview(button)
        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: glass.contentView.leadingAnchor),
            button.trailingAnchor.constraint(equalTo: glass.contentView.trailingAnchor),
            button.topAnchor.constraint(equalTo: glass.contentView.topAnchor),
            button.bottomAnchor.constraint(equalTo: glass.contentView.bottomAnchor),
        ])
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
        cameraStatusPanel?.isHidden = true
        shutter.isEnabled = true
        shutter.alpha = 1
        flashButton.isEnabled = captureDevice?.hasFlash == true
        flashButton.alpha = flashButton.isEnabled ? 1 : 0.45
        cameraSwitchButton.isEnabled = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) != nil
            && AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil
        cameraSwitchButton.alpha = cameraSwitchButton.isEnabled ? 1 : 0.45
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
                message: "相机已授权，但预览画面还没有准备好。\n请点击重试，或切换前后摄像头。",
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
        flashButton.isEnabled = false
        flashButton.alpha = 0.45
        cameraSwitchButton.isEnabled = false
        cameraSwitchButton.alpha = 0.45
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
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil,
              let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else {
            DispatchQueue.main.async { [weak self] in
                self?.shutter.isEnabled = true
                self?.shutter.alpha = 1
            }
            return
        }
        DispatchQueue.main.async { [weak self] in
            self?.stopSession()
            self?.onImage?(image)
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
            picker.dismiss(animated: true) { [weak self] in self?.authorizeAndStartCamera() }
            return
        }

        guard provider.canLoadObject(ofClass: UIImage.self) else {
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
                    picker?.dismiss(animated: true) {
                        self.showCameraStatus(
                            message: "无法读取这张照片，请重新选择。",
                            symbol: "photo.badge.exclamationmark"
                        )
                    }
                    return
                }
                picker?.dismiss(animated: true) {
                    self.onImage?(image)
                }
            }
        }
    }
}

private final class CameraGuideView: UIView {
    var isGridVisible = false { didSet { updateGuidePath() } }
    private var focusPoint: CGPoint? { didSet { updateGuidePath() } }
    private let guideLayer = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        isUserInteractionEnabled = false
        guideLayer.fillColor = UIColor.clear.cgColor
        guideLayer.lineCap = .round
        guideLayer.lineJoin = .round
        layer.addSublayer(guideLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guideLayer.frame = bounds
        updateGuidePath()
    }

    private func updateGuidePath() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let guide = bounds.insetBy(dx: 28, dy: 154).inset(by: UIEdgeInsets(top: 0, left: 0, bottom: 40, right: 0))
        let path = UIBezierPath()
        let length: CGFloat = 34
        let corners = [
            (CGPoint(x: guide.minX, y: guide.minY), CGPoint(x: guide.minX + length, y: guide.minY), CGPoint(x: guide.minX, y: guide.minY + length)),
            (CGPoint(x: guide.maxX, y: guide.minY), CGPoint(x: guide.maxX - length, y: guide.minY), CGPoint(x: guide.maxX, y: guide.minY + length)),
            (CGPoint(x: guide.minX, y: guide.maxY), CGPoint(x: guide.minX + length, y: guide.maxY), CGPoint(x: guide.minX, y: guide.maxY - length)),
            (CGPoint(x: guide.maxX, y: guide.maxY), CGPoint(x: guide.maxX - length, y: guide.maxY), CGPoint(x: guide.maxX, y: guide.maxY - length)),
        ]
        for (corner, horizontal, vertical) in corners {
            path.move(to: horizontal)
            path.addLine(to: corner)
            path.addLine(to: vertical)
        }

        if isGridVisible {
            for fraction in [CGFloat(1.0 / 3.0), CGFloat(2.0 / 3.0)] {
                path.move(to: CGPoint(x: guide.minX + guide.width * fraction, y: guide.minY))
                path.addLine(to: CGPoint(x: guide.minX + guide.width * fraction, y: guide.maxY))
                path.move(to: CGPoint(x: guide.minX, y: guide.minY + guide.height * fraction))
                path.addLine(to: CGPoint(x: guide.maxX, y: guide.minY + guide.height * fraction))
            }
        }

        if let focusPoint {
            path.append(UIBezierPath(ovalIn: CGRect(x: focusPoint.x - 32, y: focusPoint.y - 32, width: 64, height: 64)))
        }

        guideLayer.path = path.cgPath
        guideLayer.lineWidth = isGridVisible ? 1.5 : 2
        guideLayer.strokeColor = focusPoint == nil
            ? UIColor.white.withAlphaComponent(0.74).cgColor
            : UIColor(red: 0.96, green: 0.79, blue: 0.37, alpha: 0.94).cgColor
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
