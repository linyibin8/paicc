import UIKit
import AVFoundation
import Vision

// MARK: - 手势类型

enum GestureType: String, CaseIterable {
    case pointing      // 食指指向 - 截取题目
    case ok            // OK 手势 - 打断问答
    case peace         // ✌️ 手势 - 结束本轮
    case raisedHand    // 举手
}

// MARK: - CameraService

/// 相机服务 - 管理相机采集和手势检测
class CameraService: NSObject {

    // MARK: - 常量

    private let gestureDetectionThreshold: Int = 4  // 连续 4 帧检测到才算有效

    // MARK: - 状态

    enum CaptureState {
        case idle
        case scanning
        case capturing
    }

    private(set) var captureState: CaptureState = .idle
    private(set) var isCapturing = false

    // MARK: - 属性

    private var captureSession: AVCaptureSession?
    private var videoOutput: AVCaptureVideoDataOutput?
    private(set) var previewLayer: AVCaptureVideoPreviewLayer?
    private var currentVideoOutput: AVCaptureVideoDataOutput?

    private let sessionQueue = DispatchQueue(label: "com.paicc.camera.session")
    private let processingQueue = DispatchQueue(label: "com.paicc.camera.processing")

    // 手势检测
    private var handPoseRequest: VNDetectHumanHandPoseRequest!
    private var gestureFrameCount: [GestureType: Int] = [:]
    private var isGestureDetectionEnabled = false

    // 回调
    var onFrameCaptured: ((UIImage) -> Void)?
    var onGestureDetected: ((GestureType) -> Void)?
    var onHandPresenceChanged: ((Bool) -> Void)?

    // MARK: - 初始化

    override init() {
        super.init()
        setupVision()
    }

    // MARK: - 相机配置

    func setupCamera(in view: UIView) {
        captureSession = AVCaptureSession()
        captureSession?.sessionPreset = .high

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: camera) else {
            print("CameraService: 无法获取相机")
            return
        }

        if captureSession?.canAddInput(input) == true {
            captureSession?.addInput(input)
        }

        videoOutput = AVCaptureVideoDataOutput()
        videoOutput?.setSampleBufferDelegate(self, queue: processingQueue)
        videoOutput?.alwaysDiscardsLateVideoFrames = true

        if captureSession?.canAddOutput(videoOutput!) == true {
            captureSession?.addOutput(videoOutput!)
        }

        // 设置预览层
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession!)
        previewLayer?.videoGravity = .resizeAspectFill
        previewLayer?.frame = view.bounds
        view.layer.insertSublayer(previewLayer!, at: 0)
    }

    // MARK: - Vision 设置

    private func setupVision() {
        handPoseRequest = VNDetectHumanHandPoseRequest()
    }

    // MARK: - 控制

    func startCapture() {
        sessionQueue.async { [weak self] in
            self?.captureSession?.startRunning()
            self?.captureState = .scanning
        }
    }

    func stopCapture() {
        isGestureDetectionEnabled = false
        sessionQueue.async { [weak self] in
            self?.captureSession?.stopRunning()
            self?.captureState = .idle
        }
    }

    func enableGestureDetection() {
        isGestureDetectionEnabled = true
        resetGestureCounts()
    }

    func disableGestureDetection() {
        isGestureDetectionEnabled = false
        resetGestureCounts()
    }

    // MARK: - 截取当前帧

    func captureCurrentFrame() -> UIImage? {
        guard let previewLayer = previewLayer else { return nil }

        let renderer = UIGraphicsImageRenderer(bounds: previewLayer.bounds)
        return renderer.image { context in
            previewLayer.render(in: context.cgContext)
        }
    }

    // MARK: - 手势检测

    private func detectGesture(from observation: VNHumanHandPoseObservation) -> GestureType? {
        do {
            let fingers = try observation.recognizedPoints(.all)

            // 检查食指是否伸直（指向手势）
            if isIndexExtended(fingers) && !isThumbExtended(fingers) {
                return .pointing
            }

            // 检查 OK 手势（拇指和食指指尖相触）
            if isOkGesture(fingers) {
                return .ok
            }

            // 检查 ✌️ 手势（食指和中指伸直）
            if isPeaceGesture(fingers) {
                return .peace
            }

            return nil

        } catch {
            return nil
        }
    }

    private func isIndexExtended(_ fingers: [VNHumanHandPoseObservation.JointName: VNRecognizedPoint]) -> Bool {
        guard let indexTip = fingers[.indexTip],
              let indexMCP = fingers[.indexMCP],
              let indexPIP = fingers[.indexPIP] else { return false }

        let tipToMcp = distance(indexTip.location, indexMCP.location)
        let pipToMcp = distance(indexPIP.location, indexMCP.location)

        return tipToMcp > pipToMcp * 1.2
    }

    private func isThumbExtended(_ fingers: [VNHumanHandPoseObservation.JointName: VNRecognizedPoint]) -> Bool {
        guard let thumbTip = fingers[.thumbTip],
              let thumbIP = fingers[.thumbIP],
              let wrist = fingers[.wrist] else { return false }

        let tipToWrist = distance(thumbTip.location, wrist.location)
        let ipToWrist = distance(thumbIP.location, wrist.location)

        return tipToWrist > ipToWrist * 1.1
    }

    private func isOkGesture(_ fingers: [VNHumanHandPoseObservation.JointName: VNRecognizedPoint]) -> Bool {
        guard let thumbTip = fingers[.thumbTip],
              let indexTip = fingers[.indexTip] else { return false }

        return distance(thumbTip.location, indexTip.location) < 0.05
    }

    private func isPeaceGesture(_ fingers: [VNHumanHandPoseObservation.JointName: VNRecognizedPoint]) -> Bool {
        guard let indexTip = fingers[.indexTip],
              let middleTip = fingers[.middleTip],
              let indexMCP = fingers[.indexMCP],
              let middleMCP = fingers[.middleMCP] else { return false }

        let indexExtended = distance(indexTip.location, indexMCP.location)
        let middleExtended = distance(middleTip.location, middleMCP.location)

        return indexExtended > 0.1 && middleExtended > 0.1
    }

    private func distance(_ p1: CGPoint, _ p2: CGPoint) -> CGFloat {
        return sqrt(pow(p1.x - p2.x, 2) + pow(p1.y - p2.y, 2))
    }

    // MARK: - 手势计数

    private func incrementGestureCount(_ gesture: GestureType) {
        gestureFrameCount[gesture, default: 0] += 1
    }

    private func getGestureCount(_ gesture: GestureType) -> Int {
        return gestureFrameCount[gesture] ?? 0
    }

    private func resetGestureCounts() {
        GestureType.allCases.forEach { gestureFrameCount[$0] = 0 }
    }

    private func triggerGesture(_ gesture: GestureType) {
        DispatchQueue.main.async { [weak self] in
            self?.onGestureDetected?(gesture)
        }
    }

    // MARK: - 处理帧

    private func processFrame(_ pixelBuffer: CVPixelBuffer) {
        guard isGestureDetectionEnabled else { return }

        do {
            try sequenceHandler.perform([handPoseRequest], on: pixelBuffer, orientation: .up)

            guard let observation = handPoseRequest.results?.first else {
                resetGestureCounts()
                return
            }

            let gesture = detectGesture(from: observation)
            if let gesture = gesture {
                incrementGestureCount(gesture)

                if getGestureCount(gesture) >= gestureDetectionThreshold {
                    triggerGesture(gesture)
                    resetGestureCounts()
                }
            } else {
                resetGestureCounts()
            }

        } catch {
            // 忽略检测错误
        }
    }

    private let sequenceHandler = VNSequenceRequestHandler()
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraService: AVCaptureVideoDataOutputSampleBufferDelegate {

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // 手势检测（每帧都检测）
        if isGestureDetectionEnabled {
            processFrame(pixelBuffer)
        }
    }
}

