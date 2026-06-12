import Vision
import AVFoundation
import UIKit

/// 手势识别服务
class GestureService {

    // MARK: - 手势类型
    enum GestureType {
        case pointing      // 食指指向
        case ok            // OK 手势
        case peace         // ✌️ 手势
        case raisedHand    // 举手
    }

    // MARK: - 配置
    private var isRunning = false
    private let detectionThreshold: Int = 4  // 连续 4 帧检测到才算有效
    private var gestureFrameCount: [GestureType: Int] = [:]

    // MARK: - Vision
    private var handPoseRequest: VNDetectHumanHandPoseRequest!
    private let sequenceHandler = VNSequenceRequestHandler()

    // MARK: - 初始化

    init() {
        setupVision()
    }

    private func setupVision() {
        handPoseRequest = VNDetectHumanHandPoseRequest()
    }

    // MARK: - 控制

    func startDetection() {
        guard !isRunning else { return }
        isRunning = true

        // 清空计数
        GestureType.allCases.forEach { gestureFrameCount[$0] = 0 }
    }

    func stopDetection() {
        isRunning = false
    }

    // MARK: - 处理帧

    func processFrame(_ pixelBuffer: CVPixelBuffer) {
        guard isRunning else { return }

        do {
            try sequenceHandler.perform([handPoseRequest], on: pixelBuffer, orientation: .up)

            guard let observation = handPoseRequest.results?.first else {
                resetGestureCounts()
                return
            }

            let gesture = detectGesture(from: observation)
            if let gesture = gesture {
                incrementGestureCount(gesture)

                if getGestureCount(gesture) >= detectionThreshold {
                    triggerGesture(gesture)
                    resetGestureCounts()
                }
            } else {
                resetGestureCounts()
            }

        } catch {
            print("Hand pose detection error: \(error)")
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

            // 检查举手
            if isRaisedHand(fingers) {
                return .raisedHand
            }

            return nil

        } catch {
            return nil
        }
    }

    private func isIndexExtended(_ fingers: [VNHumanHandPoseObservation.JointName: VNRecognizedPoint]) -> Bool {
        // 检查食指各关节
        let indexTip = fingers[.indexTip]
        let indexMCP = fingers[.indexMCP]
        let indexPIP = fingers[.indexPIP]

        guard let tip = indexTip, let mcp = indexMCP, let pip = indexPIP else { return false }

        // 手指伸直意味着指尖到 MCP 的距离大于 PIP 到 MCP 的距离
        let tipToMcp = distance(tip.location, mcp.location)
        let pipToMcp = distance(pip.location, mcp.location)

        return tipToMcp > pipToMcp * 1.2
    }

    private func isThumbExtended(_ fingers: [VNHumanHandPoseObservation.JointName: VNRecognizedPoint]) -> Bool {
        let thumbTip = fingers[.thumbTip]
        let thumbIP = fingers[.thumbIP]

        guard let tip = thumbTip, let ip = thumbIP else { return false }

        let tipToWrist = distance(tip.location, fingers[.wrist]?.location ?? .zero)
        let ipToWrist = distance(ip.location, fingers[.wrist]?.location ?? .zero)

        return tipToWrist > ipToWrist * 1.1
    }

    private func isOkGesture(_ fingers: [VNHumanHandPoseObservation.JointName: VNRecognizedPoint]) -> Bool {
        guard let thumbTip = fingers[.thumbTip],
              let indexTip = fingers[.indexTip] else { return false }

        let distance = self.distance(thumbTip.location, indexTip.location)
        return distance < 0.05  // 拇指和食指相触
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

    private func isRaisedHand(_ fingers: [VNHumanHandPoseObservation.JointName: VNRecognizedPoint]) -> Bool {
        // 检查所有手指是否伸直
        let extendedCount = [GestureType.pointing, .ok, .peace]
            .filter { _ in true }  // 简化检查

        guard let wrist = fingers[.wrist] else { return false }

        var count = 0
        let tipKeys: [VNHumanHandPoseObservation.JointName] = [.indexTip, .middleTip, .ringTip, .littleTip]
        for tipKey in tipKeys {
            if let tip = fingers[tipKey] {
                let dist = distance(tip.location, wrist.location)
                if dist > 0.3 { count += 1 }
            }
        }

        return count >= 3
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
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .gestureDetected,
                object: nil,
                userInfo: ["gesture": gesture]
            )
        }
    }
}

// MARK: - GestureType Extension

extension GestureService.GestureType: CaseIterable {
    static var allCases: [GestureService.GestureType] {
        return [.pointing, .ok, .peace, .raisedHand]
    }
}