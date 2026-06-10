//
//  手势识别服务
//  使用 Vision Framework 检测手势
//

import Vision
import AVFoundation
import UIKit

@MainActor
class GestureService: ObservableObject {
    @Published var currentGesture: GestureType = .none
    @Published var isDetecting: Bool = false

    private var handPoseRequest: VNDetectHumanHandPoseRequest!
    private var frameCounter: Int = 0
    private let stableFrameThreshold: Int = 4  // 连续 4 帧稳定

    private var lastPointingFrame: CGRect?
    private var stableCount: Int = 0

    enum GestureType: String {
        case none = "无"
        case pointing = "指向"       // 食指伸出
        case ok = "OK"              // OK 手势
        case peace = "耶"           // 双耶
        case thumbsUp = "点赞"
        case thumbsDown = "差评"
        case call = "打电话"
    }

    init() {
        setupVision()
    }

    private func setupVision() {
        handPoseRequest = VNDetectHumanHandPoseRequest()
        handPoseRequest.maximumHandCount = 1
    }

    func startDetection() {
        isDetecting = true
        frameCounter = 0
    }

    func stopDetection() {
        isDetecting = false
        frameCounter = 0
        stableCount = 0
        currentGesture = .none
    }

    func processFrame(_ pixelBuffer: CVPixelBuffer) {
        guard isDetecting else { return }

        do {
            try handPoseRequest.perform(on: pixelBuffer)

            guard let observation = handPoseRequest.results?.first else {
                resetDetection()
                return
            }

            // 分析手势
            let gesture = analyzeHandPose(observation)

            if gesture == currentGesture {
                stableCount += 1
                if stableCount >= stableFrameThreshold {
                    // 手势稳定，触发事件
                    handleStableGesture(gesture)
                }
            } else {
                currentGesture = gesture
                stableCount = 1
            }

            frameCounter += 1

        } catch {
            print("Hand pose detection error: \(error)")
        }
    }

    private func analyzeHandPose(_ observation: VNHumanHandPoseObservation) -> GestureType {
        // 获取关键点
        guard let wrist = try? observation.recognizedPoint(.wrist),
              let thumbTip = try? observation.recognizedPoint(.thumbTip),
              let indexTip = try? observation.recognizedPoint(.indexTip),
              let middleTip = try? observation.recognizedPoint(.middleTip),
              let ringTip = try? observation.recognizedPoint(.ringTip),
              let littleTip = try? observation.recognizedPoint(.littleTip) else {
            return .none
        }

        // 计算手指伸展情况
        let indexExtended = indexTip.confidence > 0.5 &&
                            indexTip.location.y < wrist.location.y
        let middleExtended = middleTip.confidence > 0.5 &&
                            middleTip.location.y < wrist.location.y
        let ringExtended = ringTip.confidence > 0.5 &&
                           ringTip.location.y < wrist.location.y
        let littleExtended = littleTip.confidence > 0.5 &&
                             littleTip.location.y < wrist.location.y

        // 只有食指伸出（指向手势）
        if indexExtended && !middleExtended && !ringExtended && !littleExtended {
            return .pointing
        }

        // 耶手势（食指和中指伸出）
        if indexExtended && middleExtended && !ringExtended && !littleExtended {
            return .peace
        }

        // OK 手势（拇指和食指接触）
        if thumbTip.confidence > 0.5 && indexTip.confidence > 0.5 {
            let distance = hypot(thumbTip.location.x - indexTip.location.x,
                                thumbTip.location.y - indexTip.location.y)
            if distance < 0.1 {
                return .ok
            }
        }

        // 拇指朝上
        if thumbTip.confidence > 0.5 &&
           thumbTip.location.y < wrist.location.y &&
           !indexExtended {
            return .thumbsUp
        }

        return .none
    }

    private func handleStableGesture(_ gesture: GestureType) {
        // 根据手势类型处理
        switch gesture {
        case .pointing:
            NotificationCenter.default.post(
                name: .gesturePointingDetected,
                object: nil
            )
        case .ok:
            NotificationCenter.default.post(
                name: .gestureOKDetected,
                object: nil
            )
        case .peace:
            NotificationCenter.default.post(
                name: .gesturePeaceDetected,
                object: nil
            )
        default:
            break
        }
    }

    private func resetDetection() {
        currentGesture = .none
        stableCount = 0
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let gesturePointingDetected = Notification.Name("gesturePointingDetected")
    static let gestureOKDetected = Notification.Name("gestureOKDetected")
    static let gesturePeaceDetected = Notification.Name("gesturePeaceDetected")
}