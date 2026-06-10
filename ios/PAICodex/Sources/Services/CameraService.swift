//
//  相机采集服务
//  使用 AVFoundation 实现实时视频流捕获
//

import AVFoundation
import UIKit
import Vision

@MainActor
class CameraService: ObservableObject {
    @Published var currentFrame: UIImage?
    @Published var isCapturing: Bool = false
    @Published var capturedImage: UIImage?

    private var captureSession: AVCaptureSession?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var photoOutput: AVCapturePhotoOutput?

    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    private var frameProcessingCallback: ((CVPixelBuffer) -> Void)?

    init() {}

    // MARK: - 启动捕获

    func startCapture() {
        isCapturing = true
        sessionQueue.async { [weak self] in
            self?.setupCaptureSession()
        }
    }

    func stopCapture() {
        isCapturing = false
        captureSession?.stopRunning()
    }

    private func setupCaptureSession() {
        let session = AVCaptureSession()
        session.sessionPreset = .hd1280x720  // 720p 足够用于手势识别

        // 获取摄像头
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else {
            print("Camera not available")
            return
        }

        if session.canAddInput(input) {
            session.addInput(input)
        }

        // 视频输出（用于手势识别）
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOutput.setSampleBufferDelegate(VideoOutputDelegate.shared, queue: sessionQueue)

        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        }
        self.videoOutput = videoOutput

        // 照片输出
        let photoOutput = AVCapturePhotoOutput()
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
        }
        self.photoOutput = photoOutput

        self.captureSession = session
        VideoOutputDelegate.shared.cameraService = self

        session.startRunning()
    }

    // MARK: - 截取当前帧

    func captureCurrentFrame() -> UIImage? {
        return currentFrame
    }

    func capturePhoto(completion: @escaping (UIImage?) -> Void) {
        guard let photoOutput = photoOutput else {
            completion(nil)
            return
        }

        let settings = AVCapturePhotoSettings()
        settings.flashMode = .off

        let delegate = PhotoCaptureDelegate { image in
            completion(image)
        }

        photoOutput.capturePhoto(with: settings, delegate: delegate)
    }

    // MARK: - 帧处理

    func setFrameProcessingCallback(_ callback: @escaping (CVPixelBuffer) -> Void) {
        frameProcessingCallback = callback
    }

    func processFrame(_ pixelBuffer: CVPixelBuffer) {
        Task { @MainActor in
            // 转换为 UIImage（用于显示）
            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            let context = CIContext()
            if let cgImage = context.createCGImage(ciImage, from: ciImage.extent) {
                currentFrame = UIImage(cgImage: cgImage)
            }

            // 调用回调（用于手势识别）
            frameProcessingCallback?(pixelBuffer)
        }
    }
}

// MARK: - Video Output Delegate

class VideoOutputDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    static let shared = VideoOutputDelegate()
    weak var cameraService: CameraService?

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        Task { @MainActor in
            cameraService?.processFrame(pixelBuffer)
        }
    }
}

// MARK: - Photo Capture Delegate

class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private let completion: (UIImage?) -> Void

    init(completion: @escaping (UIImage?) -> Void) {
        self.completion = completion
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else {
            completion(nil)
            return
        }
        completion(image)
    }
}