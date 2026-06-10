//
//  问答浮层视图
//

import SwiftUI

struct QAOverlayView: View {
    let answer: String
    let recognizedQuery: String
    let onDismiss: () -> Void
    let onInterrupt: () -> Void

    @EnvironmentObject var appState: AppState
    @State private var displayText: String = ""
    @State private var showInterruptHint: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // 顶部栏
            HStack {
                Text("AI 回答")
                    .font(.headline)
                    .foregroundColor(.white)

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            .padding()
            .background(Color.blue)

            // 识别的问题
            if !recognizedQuery.isEmpty {
                HStack {
                    Image(systemName: "mic.fill")
                        .foregroundColor(.red)
                    Text(recognizedQuery)
                        .font(.subheadline)
                        .foregroundColor(.gray)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color.gray.opacity(0.1))
            }

            // 回答内容
            ScrollView {
                Text(displayText)
                    .font(.body)
                    .foregroundColor(.primary)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 300)

            // 底部操作区
            VStack(spacing: 12) {
                // 打断提示
                if showInterruptHint {
                    HStack {
                        Image(systemName: "hand.raised.fill")
                        Text("说「继续」或 ✌️ 手势继续追问")
                    }
                    .font(.caption)
                    .foregroundColor(.orange)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 16)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(20)
                }

                // 操作按钮
                HStack(spacing: 20) {
                    Button(action: onInterrupt) {
                        HStack {
                            Image(systemName: "hand.tap.fill")
                            Text("追问")
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.blue.opacity(0.1))
                        .foregroundColor(.blue)
                        .cornerRadius(20)
                    }

                    Button(action: onDismiss) {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                            Text("完成")
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.green.opacity(0.1))
                        .foregroundColor(.green)
                        .cornerRadius(20)
                    }
                }
            }
            .padding()
            .background(Color.gray.opacity(0.05))
        }
        .background(Color.white)
        .cornerRadius(16)
        .shadow(radius: 10)
        .padding()
        .onAppear {
            animateText()
        }
    }

    private func animateText() {
        // 打字机效果
        displayText = ""
        var index = answer.startIndex

        Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { timer in
            if index < answer.endIndex {
                displayText.append(answer[index])
                index = answer.index(after: index)
            } else {
                timer.invalidate()
                showInterruptHint = true
            }
        }
    }
}

// MARK: - 手势识别视图

struct GestureIndicatorView: View {
    let gesture: GestureService.GestureType

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: gestureIcon)
                .font(.system(size: 40))
                .foregroundColor(gestureColor)

            Text(gesture.rawValue)
                .font(.caption)
                .foregroundColor(gestureColor)
        }
        .padding()
        .background(gestureColor.opacity(0.1))
        .cornerRadius(12)
        .opacity(gesture == .none ? 0 : 1)
    }

    private var gestureIcon: String {
        switch gesture {
        case .none: return "hand.raised"
        case .pointing: return "hand.point.up.fill"
        case .ok: return "hand.raised.fill"
        case .peace: return "peace.sign"
        case .thumbsUp: return "hand.thumbsup.fill"
        case .thumbsDown: return "hand.thumbsdown.fill"
        case .call: return "phone.fill"
        }
    }

    private var gestureColor: Color {
        switch gesture {
        case .none: return .gray
        case .pointing: return .blue
        case .ok: return .green
        case .peace: return .orange
        case .thumbsUp: return .green
        case .thumbsDown: return .red
        case .call: return .purple
        }
    }
}

// MARK: - 语音识别状态视图

struct SpeechRecognitionView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 16) {
            // 麦克风动画
            Image(systemName: "mic.fill")
                .font(.system(size: 40))
                .foregroundColor(.red)
                .scaleEffect(appState.speechService.isListening ? 1.2 : 1.0)
                .animation(
                    appState.speechService.isListening ?
                        Animation.easeInOut(duration: 0.5).repeatForever(autoreverses: true) :
                        .default,
                    value: appState.speechService.isListening
                )

            // 识别文字
            if appState.speechService.isListening {
                Text(appState.speechService.recognizedText.isEmpty ? "请说话..." : appState.speechService.recognizedText)
                    .font(.body)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
            }

            // 提示
            Text("3秒沉默后自动结束")
                .font(.caption)
                .foregroundColor(.gray)
        }
        .padding()
        .background(Color.white)
        .cornerRadius(16)
        .shadow(radius: 5)
    }
}