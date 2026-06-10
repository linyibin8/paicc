import AVFoundation
import UIKit

/// 相机服务 - 处理画面采集
class CameraService: NSObject {

    // MARK: - 属性
    let captureSession = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "camera.session.queue")

    var previewLayer: AVCaptureVideoPreviewLayer {
        let layer = AVCaptureVideoPreviewLayer(session: captureSession)
        layer.videoGravity = .resizeAspectFill
        return layer
    }

    private var currentFrame: CVPixelBuffer?
    private let frameLock = NSLock()

    // MARK: - 回调
    var onFrameCaptured: ((CVPixelBuffer) -> Void)?

    // MARK: - 初始化

    override init() {
        super.init()
        setupCamera()
    }

    private func setupCamera() {
        sessionQueue.async { [weak self] in
            self?.configureSession()
        }
    }

    private func configureSession() {
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .hd1280x720

        // 添加视频输入
        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let videoInput = try? AVCaptureDeviceInput(device: videoDevice) else {
            captureSession.commitConfiguration()
            return
        }

        if captureSession.canAddInput(videoInput) {
            captureSession.addInput(videoInput)
        }

        // 添加视频输出
        videoOutput.setSampleBufferDelegate(self, queue: sessionQueue)
        videoOutput.alwaysDiscardsLateVideoFrames = true

        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        }

        captureSession.commitConfiguration()
    }

    // MARK: - 控制

    func startCapture() {
        sessionQueue.async { [weak self] in
            if self?.captureSession.isRunning == false {
                self?.captureSession.startRunning()
            }
        }
    }

    func stopCapture() {
        sessionQueue.async { [weak self] in
            if self?.captureSession.isRunning == true {
                self?.captureSession.stopRunning()
            }
        }
    }

    // MARK: - 截取当前帧

    func captureCurrentFrame() -> UIImage? {
        frameLock.lock()
        defer { frameLock.unlock() }

        guard let pixelBuffer = currentFrame else { return nil }
        return pixelBuffer.toUIImage()
    }

    func captureCurrentFrameData() -> Data? {
        guard let image = captureCurrentFrame() else { return nil }
        return image.jpegData(compressionQuality: 0.8)
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraService: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // 保存当前帧
        frameLock.lock()
        currentFrame = pixelBuffer
        frameLock.unlock()

        // 通知回调
        DispatchQueue.main.async { [weak self] in
            self?.onFrameCaptured?(pixelBuffer)
        }
    }
}

// MARK: - CVPixelBuffer 扩展

extension CVPixelBuffer {
    func toUIImage() -> UIImage? {
        let ciImage = CIImage(cvPixelBuffer: self)
        let context = CIContext()

        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }
}