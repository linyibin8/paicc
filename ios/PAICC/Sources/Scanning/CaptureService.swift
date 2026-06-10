import UIKit
import AVFoundation
import Vision

protocol CaptureServiceDelegate: AnyObject {
    func captureService(_ service: CaptureService, didCaptureFrame image: UIImage)
    func captureService(_ service: CaptureService, didDetectHandPresence: Bool)
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

    private(set) var isRunning: Bool = false

    private weak var previewView: UIView?

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
        // 简单的帧变化检测
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        frameCount += 1

        // 每30帧进行一次分析（约每秒一次）
        if frameCount % 30 == 0 {
            detectHandPresence(in: pixelBuffer)
        }
    }

    private func detectHandPresence(in pixelBuffer: CVPixelBuffer) {
        let request = VNDetectHumanHandposeRequest { [weak self] request, error in
            guard let observations = request.results as? [VNHumanHandposeObservation],
                  !observations.isEmpty else {
                self?.delegate?.captureService(self!, didDetectHandPresence: false)
                return
            }

            self?.delegate?.captureService(self!, didDetectHandPresence: true)
        }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        try? handler.perform([request])
    }
}