import UIKit
import AVFoundation
import Vision
import CoreImage

protocol CaptureServiceDelegate: AnyObject {
    func captureService(_ service: CaptureService, didCaptureFrame image: UIImage, meta: CaptureMeta)
    func captureService(_ service: CaptureService, didDetectHandPresence: Bool)
    func captureService(_ service: CaptureService, didUpdateState state: CaptureServiceState)
}

/// 采集服务状态
enum CaptureServiceState {
    case idle
    case capturing
    case processing
    case uploading
}

/// 采集元数据
struct CaptureMeta: Codable {
    var capture_id: String
    var timestamp: String
    var sequence: Int
    var frame_fingerprint: String
    var quality_score: Float
    var student_present: Bool
    var content_type: String  // textbook, exam, blank, other
    var session_id: String?
    var trigger_type: String?  // auto, gesture, voice

    enum CodingKeys: String, CodingKey {
        case capture_id, timestamp, sequence
        case frame_fingerprint, quality_score
        case student_present, content_type
        case session_id, trigger_type
    }
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
    private var captureSequence: Int = 0
    private var lastFingerprint: String = ""

    private(set) var isRunning: Bool = false
    private(set) var currentState: CaptureServiceState = .idle

    private weak var previewView: UIView?

    // 画面变化检测阈值
    private let pixelChangeThreshold: Float = 0.15  // 15% 像素变化
    private let qualityThreshold: Float = 0.5       // 画面质量阈值

    // 用于相似度检测的帧历史
    private var recentFingerprints: [String] = []
    private let maxFingerprintHistory: Int = 10

    init(previewView: UIView) {
        self.previewView = previewView
        super.init()
        setupCaptureSession()
    }

    private func setupCaptureSession() {
        captureSession = AVCaptureSession()
        captureSession?.sessionPreset = .hd1280x720  // 使用 720p 以平衡清晰度和性能

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
            self?.currentState = .idle
        }
    }

    func stopSession() {
        sessionQueue.async { [weak self] in
            self?.captureSession?.stopRunning()
            self?.isRunning = false
            self?.currentState = .idle
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

    // MARK: - 手动触发采集

    func triggerCapture(with triggerType: String = "gesture", sessionId: String? = nil) {
        currentState = .capturing

        guard let image = captureCurrentFrame() else {
            currentState = .idle
            return
        }

        // 生成采集元数据
        let meta = generateCaptureMeta(
            image: image,
            triggerType: triggerType,
            sessionId: sessionId
        )

        // 通知委托方
        delegate?.captureService(self, didCaptureFrame: image, meta: meta)

        currentState = .idle
    }

    // MARK: - 画面变化检测

    private func shouldCaptureThisFrame(currentHash: Int) -> Bool {
        // 如果画面变化超过阈值，应该采集
        let hashDiff = abs(currentHash - lastImageHash)
        let changeRatio = Float(hashDiff) / Float(max(lastImageHash, 1))

        return changeRatio > pixelChangeThreshold
    }

    // MARK: - 生成采集元数据

    private func generateCaptureMeta(image: UIImage, triggerType: String, sessionId: String?) -> CaptureMeta {
        captureSequence += 1

        // 计算画面指纹
        let fingerprint = calculateFingerprint(image)

        // 评估画面质量
        let qualityScore = evaluateQuality(image)

        // 检测学生是否在场
        let studentPresent = detectStudentPresence(image)

        // 分类内容类型
        let contentType = classifyContent(image)

        // 生成唯一 ID
        let captureId = "cap_\(UUID().uuidString.prefix(12))"

        // 格式化时间戳
        let formatter = ISO8601DateFormatter()
        let timestamp = formatter.string(from: Date())

        return CaptureMeta(
            capture_id: captureId,
            timestamp: timestamp,
            sequence: captureSequence,
            frame_fingerprint: fingerprint,
            quality_score: qualityScore,
            student_present: studentPresent,
            content_type: contentType,
            session_id: sessionId,
            trigger_type: triggerType
        )
    }

    // MARK: - 画面指纹计算（感知哈希简化版）

    private func calculateFingerprint(_ image: UIImage) -> String {
        guard let cgImage = image.cgImage else {
            return UUID().uuidString
        }

        // 缩小图像到 32x32 用于指纹计算
        let size = CGSize(width: 32, height: 32)
        let context = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: Int(size.width),
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        )

        context?.draw(cgImage, in: CGRect(origin: .zero, size: size))

        guard let data = context?.data else {
            return UUID().uuidString
        }

        let pixels = data.bindMemory(to: UInt8.self, capacity: 1024)

        // 计算平均灰度
        var sum: Int = 0
        for i in 0..<1024 {
            sum += Int(pixels[i])
        }
        let avg = sum / 1024

        // 计算哈希
        var hash: UInt64 = 0
        for i in 0..<1024 {
            if Int(pixels[i]) > avg {
                hash |= (1 << (i % 64))
            }
        }

        return String(format: "%016llx", hash)
    }

    // MARK: - 画面质量评估

    func evaluateQuality(_ image: UIImage) -> Float {
        guard let cgImage = image.cgImage else {
            return 0.0
        }

        // 1. 检查分辨率
        let width = cgImage.width
        let height = cgImage.height
        let resolutionScore = min(Float(min(width, height)) / 720.0, 1.0) * 0.3

        // 2. 检查对比度（简化版）
        let contrastScore = calculateContrast(image) * 0.3

        // 3. 检查是否有文字内容（通过边缘检测）
        let textScore = detectTextContent(image) * 0.4

        return resolutionScore + contrastScore + textScore
    }

    private func calculateContrast(_ image: UIImage) -> Float {
        guard let cgImage = image.cgImage else { return 0.0 }

        // 简化：检查图像的标准差
        let size = CGSize(width: 64, height: 64)
        let context = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: Int(size.width),
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        )

        context?.draw(cgImage, in: CGRect(origin: .zero, size: size))

        guard let data = context?.data else { return 0.5 }
        let pixels = data.bindMemory(to: UInt8.self, capacity: 4096)

        var sum: Int = 0
        var sumSq: Int = 0
        for i in 0..<4096 {
            sum += Int(pixels[i])
            sumSq += Int(pixels[i]) * Int(pixels[i])
        }

        let mean = Float(sum) / 4096.0
        let variance = (Float(sumSq) / 4096.0) - (mean * mean)
        let stdDev = sqrt(variance)

        // 归一化到 0-1
        return min(stdDev / 50.0, 1.0)
    }

    private func detectTextContent(_ image: UIImage) -> Float {
        // 使用边缘检测来估计文字内容
        guard let cgImage = image.cgImage else { return 0.0 }

        let size = CGSize(width: 128, height: 128)
        let context = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: Int(size.width),
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        )

        context?.draw(cgImage, in: CGRect(origin: .zero, size: size))

        guard let data = context?.data else { return 0.0 }
        let pixels = data.bindMemory(to: UInt8.self, capacity: 16384)

        // 简单边缘检测：计算相邻像素差异
        var edgeCount: Int = 0
        let threshold: Int = 30

        for y in 1..<127 {
            for x in 1..<127 {
                let idx = y * 128 + x
                let diff = abs(Int(pixels[idx]) - Int(pixels[idx - 1])) +
                           abs(Int(pixels[idx]) - Int(pixels[idx - 128]))
                if diff > threshold {
                    edgeCount += 1
                }
            }
        }

        let edgeRatio = Float(edgeCount) / Float(127 * 127 * 2)
        // 文字内容通常有较多的边缘
        return min(edgeRatio * 10, 1.0)
    }

    /// 判断画面质量是否足够好
    func isGoodQuality(_ image: UIImage) -> Bool {
        return evaluateQuality(image) >= qualityThreshold
    }

    // MARK: - 学生在场检测

    func detectStudentPresence(_ image: UIImage) -> Bool {
        // 使用 Vision 框架检测手部
        guard let cgImage = image.cgImage else { return false }

        let request = VNDetectHumanHandPoseRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: nil, options: [:])

        // 创建一个临时的 pixel buffer
        var pixelBuffer: CVPixelBuffer?
        let attrs = [kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue!,
                     kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue!]
        CVPixelBufferCreate(kCFAllocatorDefault,
                           cgImage.width,
                           cgImage.height,
                           kCVPixelFormatType_OneComponent8,
                           attrs as CFDictionary,
                           &pixelBuffer)

        guard let buffer = pixelBuffer else { return false }

        // 锁定 pixel buffer 并复制图像数据
        CVPixelBufferLockBaseAddress(buffer, [])
        let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: cgImage.width,
            height: cgImage.height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        )
        context?.draw(cgImage, in: CGRect(origin: .zero, size: CGSize(width: cgImage.width, height: cgImage.height)))
        CVPixelBufferUnlockBaseAddress(buffer, [])

        do {
            try handler.perform([request])
            return request.results?.isEmpty == false
        } catch {
            return false
        }
    }

    /// 异步检测学生是否在场
    func checkStudentPresenceAsync(_ image: UIImage, completion: @escaping (Bool) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let present = self?.detectStudentPresence(image) ?? false
            DispatchQueue.main.async {
                completion(present)
            }
        }
    }

    // MARK: - 内容类型分类

    func classifyContent(_ image: UIImage) -> String {
        let quality = evaluateQuality(image)

        // 如果质量太低，判定为空白
        if quality < 0.3 {
            return "blank"
        }

        // 简化分类逻辑
        // 实际应该结合 ML 模型或 OCR 结果
        return "other"  // 默认返回其他，需要后续通过后端分析来确定具体类型
    }

    /// 异步分类内容类型
    func classifyContentAsync(_ image: UIImage, completion: @escaping (String) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let contentType = self?.classifyContent(image) ?? "other"
            DispatchQueue.main.async {
                completion(contentType)
            }
        }
    }

    // MARK: - 重复画面检测

    func isDuplicateFrame(_ fingerprint: String, threshold: Float = 0.85) -> Bool {
        // 检查是否与最近的指纹相似
        for recentFp in recentFingerprints {
            if calculateSimilarity(fingerprint, recentFp) > threshold {
                return true
            }
        }

        // 更新历史
        recentFingerprints.append(fingerprint)
        if recentFingerprints.count > maxFingerprintHistory {
            recentFingerprints.removeFirst()
        }

        return false
    }

    private func calculateSimilarity(_ fp1: String, _ fp2: String) -> Float {
        guard fp1.count == fp2.count else { return 0 }

        // 计算汉明距离
        var diffCount = 0
        for (c1, c2) in zip(fp1, fp2) {
            if c1 != c2 {
                diffCount += 1
            }
        }

        let maxBits = fp1.count * 4  // 假设是十六进制字符串
        return 1.0 - (Float(diffCount) / Float(maxBits))
    }

    /// 清空指纹历史
    func clearFingerprintHistory() {
        recentFingerprints.removeAll()
    }

    // MARK: - 智能连拍逻辑

    func processFrameForSmartCapture(_ image: UIImage, triggerType: String = "auto", sessionId: String? = nil) {
        // 计算当前帧的指纹
        let fingerprint = calculateFingerprint(image)

        // 检查是否重复
        if isDuplicateFrame(fingerprint) {
            return  // 跳过重复帧
        }

        // 评估画面质量
        guard isGoodQuality(image) else {
            return  // 跳过质量太低的帧
        }

        // 更新最后指纹
        lastFingerprint = fingerprint
        lastImageHash = fingerprint.hashValue

        // 生成元数据
        let meta = generateCaptureMeta(image: image, triggerType: triggerType, sessionId: sessionId)

        // 通知委托方
        delegate?.captureService(self, didCaptureFrame: image, meta: meta)
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
extension CaptureService: AVCaptureVideoDataOutputSampleBufferDelegate {

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        frameCount += 1
        currentState = .processing

        // 每30帧进行一次分析（约每秒一次）
        if frameCount % 30 == 0 {
            // 智能连拍检测
            let image = pixelBufferToImage(pixelBuffer)

            // 检测画面变化
            let currentHash = image.hashValue
            if shouldCaptureThisFrame(currentHash: currentHash) {
                // 触发自动采集
                processFrameForSmartCapture(image, triggerType: "auto", sessionId: nil)
            }

            // 检测手部存在
            detectHandPresence(in: pixelBuffer)
        }

        currentState = .idle
    }

    private func pixelBufferToImage(_ pixelBuffer: CVPixelBuffer) -> UIImage {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()

        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            return UIImage()
        }

        return UIImage(cgImage: cgImage)
    }

    private func detectHandPresence(in pixelBuffer: CVPixelBuffer) {
        let request = VNDetectHumanHandPoseRequest { [weak self] request, error in
            guard let observations = request.results as? [VNHumanHandPoseObservation],
                  !observations.isEmpty else {
                DispatchQueue.main.async {
                    self?.delegate?.captureService(self!, didDetectHandPresence: false)
                }
                return
            }

            DispatchQueue.main.async {
                self?.delegate?.captureService(self!, didDetectHandPresence: true)
            }
        }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        try? handler.perform([request])
    }
}