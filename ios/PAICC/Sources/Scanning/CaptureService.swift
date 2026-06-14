import UIKit
import AVFoundation
import Vision
import CoreImage

protocol CaptureServiceDelegate: AnyObject {
    func captureService(_ service: CaptureService, didCaptureFrame image: UIImage)
    func captureService(_ service: CaptureService, didDetectHandPresence: Bool)
    func captureService(_ service: CaptureService, shouldSaveKeyFrame image: UIImage, reason: CaptureReason)
}

enum CaptureReason: String {
    case learningMaterialDetected = "学习材料入镜"
    case pageChanged = "页面变化"
    case writingDetected = "书写动作"
    case questionDetected = "题目出现"
    case handAppeared = "手出现"
    case manual = "手动保存"
}

class CaptureService: NSObject {

    weak var delegate: CaptureServiceDelegate?

    private var captureSession: AVCaptureSession?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var previewLayer: AVCaptureVideoPreviewLayer?

    private let sessionQueue = DispatchQueue(label: "com.paicc.capture.session")
    private let processingQueue = DispatchQueue(label: "com.paicc.capture.processing")

    private var lastFrameTime: Date = Date()
    private var frameCount: Int = 0
    private var lastImageHash: Int = 0

    // 智能连拍相关
    private var lastSavedFrame: UIImage?
    private var lastSavedTime: Date = Date()
    private var handPresenceHistory: [Bool] = []
    private var textDetectedHistory: [Bool] = []
    private var lastTextContent: String = ""
    private var captureCooldown: TimeInterval = 2.0  // 最小保存间隔

    private(set) var isRunning: Bool = false

    private weak var previewView: UIView?

    // 配置
    var isSmartCaptureEnabled: Bool = true

    init(previewView: UIView) {
        self.previewView = previewView
        super.init()
        setupCaptureSession()
    }

    private func setupCaptureSession() {
        captureSession = AVCaptureSession()
        captureSession?.sessionPreset = .high

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: camera) else {
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

        setupPreviewLayer()
    }

    private func setupPreviewLayer() {
        guard let previewView = previewView, let captureSession = captureSession else { return }

        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer?.videoGravity = .resizeAspectFill
        previewLayer?.frame = previewView.bounds

        DispatchQueue.main.async {
            previewView.layer.insertSublayer(self.previewLayer!, at: 0)
        }
    }

    func startSession() {
        sessionQueue.async { [weak self] in
            self?.captureSession?.startRunning()
            self?.isRunning = true
        }
    }

    func stopSession() {
        sessionQueue.async { [weak self] in
            self?.captureSession?.stopRunning()
            self?.isRunning = false
        }
    }

    func captureCurrentFrame() -> UIImage? {
        // 返回当前相机预览的截图
        guard let previewLayer = previewLayer else { return nil }

        let renderer = UIGraphicsImageRenderer(bounds: previewLayer.bounds)
        return renderer.image { context in
            previewLayer.render(in: context.cgContext)
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
extension CaptureService: AVCaptureVideoDataOutputSampleBufferDelegate {

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        frameCount += 1

        // 每30帧进行一次分析（约每秒一次 @ 30fps）
        if frameCount % 30 == 0 {
            // 检测手部存在
            detectHandPresence(in: pixelBuffer)

            // 智能连拍：检测画面变化
            if isSmartCaptureEnabled {
                detectSceneChange(in: pixelBuffer)
            }
        }
    }

    private func detectHandPresence(in pixelBuffer: CVPixelBuffer) {
        let request = VNDetectHumanHandPoseRequest { [weak self] request, error in
            guard let observations = request.results as? [VNHumanHandPoseObservation],
                  !observations.isEmpty else {
                self?.handPresenceHistory.append(false)
                if (self?.handPresenceHistory.count ?? 0) > 10 {
                    self?.handPresenceHistory.removeFirst()
                }
                self?.delegate?.captureService(self!, didDetectHandPresence: false)
                return
            }

            self?.handPresenceHistory.append(true)
            if (self?.handPresenceHistory.count ?? 0) > 10 {
                self?.handPresenceHistory.removeFirst()
            }
            self?.delegate?.captureService(self!, didDetectHandPresence: true)
        }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        try? handler.perform([request])
    }

    private func detectSceneChange(in pixelBuffer: CVPixelBuffer) {
        let textRequest = VNRecognizeTextRequest { [weak self] request, error in
            guard let self = self else { return }

            guard let observations = request.results as? [VNRecognizedTextObservation] else {
                return
            }

            let currentText = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
            let hasText = !currentText.isEmpty

            self.textDetectedHistory.append(hasText)
            if self.textDetectedHistory.count > 5 {
                self.textDetectedHistory.removeFirst()
            }

            // 检测是否有新内容出现
            let textChanged = !currentText.isEmpty && currentText != self.lastTextContent
            let learningMaterialDetected = self.hasLearningMaterial(in: observations)

            if textChanged || learningMaterialDetected {
                self.lastTextContent = currentText

                // 智能保存决策
                if self.shouldSaveFrame(
                    hasText: hasText,
                    textChanged: textChanged,
                    learningMaterialDetected: learningMaterialDetected
                ) {
                    self.saveKeyFrame(reason: learningMaterialDetected ? .learningMaterialDetected : .writingDetected)
                }
            }
        }

        textRequest.recognitionLevel = .fast
        textRequest.usesLanguageCorrection = false

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        try? handler.perform([textRequest])
    }

    private func hasLearningMaterial(in observations: [VNRecognizedTextObservation]) -> Bool {
        // 检测是否包含学习相关的关键词
        let keywords = ["题", "解", "答", "计算", "证明", "数学", "语文", "英语", "物理", "化学", "第", "题", "＝", "÷", "×", "+", "−"]
        let text = observations.compactMap { $0.topCandidates(1).first?.string }.joined()

        for keyword in keywords {
            if text.contains(keyword) {
                return true
            }
        }
        return false
    }

    private func shouldSaveFrame(hasText: Bool, textChanged: Bool, learningMaterialDetected: Bool) -> Bool {
        // 检查冷却时间
        let timeSinceLastSave = Date().timeIntervalSince(lastSavedTime)
        if timeSinceLastSave < captureCooldown {
            return false
        }

        // 学习材料出现或页面变化时保存
        if learningMaterialDetected || textChanged {
            return true
        }

        // 如果之前没有保存过关键帧，而现在检测到手部，可能是用户在书写
        if hasText && handPresenceHistory.last == true && lastSavedFrame == nil {
            return true
        }

        return false
    }

    private func saveKeyFrame(reason: CaptureReason) {
        guard let image = captureCurrentFrame() else { return }

        // 避免保存相同图片
        if let lastImage = lastSavedFrame, image.similarity(to: lastImage) > 0.95 {
            return
        }

        lastSavedFrame = image
        lastSavedTime = Date()

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.captureService(self, shouldSaveKeyFrame: image, reason: reason)
        }
    }

    // MARK: - 手动保存关键帧

    func saveManualKeyFrame() {
        saveKeyFrame(reason: .manual)
    }
}

// MARK: - UIImage 相似度比较

extension UIImage {
    func similarity(to other: UIImage) -> CGFloat {
        guard let cgImage1 = self.cgImage,
              let cgImage2 = other.cgImage else { return 0 }

        let ciImage1 = CIImage(cgImage: cgImage1)
        let ciImage2 = CIImage(cgImage: cgImage2)

        let context = CIContext()

        // 计算直方图相似度
        guard let filter1 = CIFilter(name: "CIAreaHistogram") else { return 0 }
        filter1.setValue(ciImage1, forKey: kCIInputImageKey)
        filter1.setValue(NSNumber(value: 64), forKey: "inputCount")
        filter1.setValue(CIVector(cgRect: ciImage1.extent), forKey: "inputExtent")

        guard let filter2 = CIFilter(name: "CIAreaHistogram") else { return 0 }
        filter2.setValue(ciImage2, forKey: kCIInputImageKey)
        filter2.setValue(NSNumber(value: 64), forKey: "inputCount")
        filter2.setValue(CIVector(cgRect: ciImage2.extent), forKey: "inputExtent")

        guard let output1 = filter1.outputImage,
              let output2 = filter2.outputImage else { return 0 }

        var bitmap1 = [UInt8](repeating: 0, count: 64 * 4)
        var bitmap2 = [UInt8](repeating: 0, count: 64 * 4)

        context.render(output1, toBitmap: &bitmap1, rowBytes: 64 * 4, bounds: CGRect(x: 0, y: 0, width: 64, height: 1), format: .RGBA8, colorSpace: nil)
        context.render(output2, toBitmap: &bitmap2, rowBytes: 64 * 4, bounds: CGRect(x: 0, y: 0, width: 64, height: 1), format: .RGBA8, colorSpace: nil)

        // 计算相似度
        var diff: CGFloat = 0
        for i in 0..<64*4 {
            diff += abs(CGFloat(bitmap1[i]) - CGFloat(bitmap2[i]))
        }

        return 1.0 - (diff / CGFloat(64 * 4 * 255))
    }
}