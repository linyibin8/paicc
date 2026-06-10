//
//  主界面视图
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var showQAOverlay: Bool = false
    @State private var currentAnswer: String = ""
    @State private var recognizedQuery: String = ""

    var body: some View {
        ZStack {
            // 背景相机画面
            CameraPreviewView()
                .ignoresSafeArea()

            // 顶部状态栏
            VStack {
                StatusBar()
                    .padding(.horizontal)
                    .padding(.top, 8)

                Spacer()
            }

            // 底部控制区
            VStack {
                Spacer()

                // 连接状态指示
                if !appState.networkService.isConnected {
                    ConnectionStatusBanner()
                }

                // 底部按钮
                BottomControlsView(
                    onQARequest: {
                        triggerQA()
                    }
                )
                .padding(.bottom, 30)
            }
        }
        .sheet(isPresented: $showQAOverlay) {
            QAOverlayView(
                answer: currentAnswer,
                recognizedQuery: recognizedQuery,
                onDismiss: {
                    showQAOverlay = false
                },
                onInterrupt: {
                    handleInterrupt()
                }
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .gesturePointingDetected)) { _ in
            // 手势触发
            handleGesturePointing()
        }
        .onReceive(NotificationCenter.default.publisher(for: .speechRecognitionComplete)) { notification in
            if let text = notification.object as? String {
                recognizedQuery = text
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .aiAnswerComplete)) { notification in
            if let answer = notification.object as? String {
                currentAnswer = answer
                showQAOverlay = true
            }
        }
    }

    private func triggerQA() {
        // 截取当前画面
        if let image = appState.cameraService.captureCurrentFrame() {
            // 开始语音识别
            appState.speechService.startListening()
        }
    }

    private func handleGesturePointing() {
        // 手势触发问答
        appState.conversationState = .listening

        // TTS 播报
        appState.speechService.speak("请说")

        // 延迟开始语音识别
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.appState.speechService.startListening()
        }
    }

    private func handleInterrupt() {
        // 处理打断
        appState.speechService.stopSpeaking()
        appState.conversationState = .listening
        appState.speechService.startListening()
    }
}

// MARK: - 状态栏

struct StatusBar: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack {
            // 连接状态
            HStack(spacing: 4) {
                Circle()
                    .fill(appState.networkService.isConnected ? Color.green : Color.red)
                    .frame(width: 8, height: 8)

                Text(appState.networkService.isConnected ? "已连接" : "未连接")
                    .font(.caption)
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.5))
            .cornerRadius(12)

            Spacer()

            // 当前状态
            Text(appState.conversationState.rawValue)
                .font(.caption)
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(stateColor.opacity(0.7))
                .cornerRadius(12)

            Spacer()

            // 会话信息
            if let session = appState.currentSession {
                Text("回合 \(session.totalCaptures)")
                    .font(.caption)
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.5))
                    .cornerRadius(12)
            }
        }
    }

    private var stateColor: Color {
        switch appState.conversationState {
        case .standby: return .gray
        case .listening: return .blue
        case .thinking: return .orange
        case .speaking: return .green
        }
    }
}

// MARK: - 连接状态横幅

struct ConnectionStatusBanner: View {
    var body: some View {
        HStack {
            Image(systemName: "wifi.exclamationmark")
            Text("服务器未连接")
            Spacer()
            Text("重试")
                .foregroundColor(.blue)
        }
        .padding()
        .background(Color.yellow.opacity(0.8))
    }
}

// MARK: - 底部控制区

struct BottomControlsView: View {
    let onQARequest: () -> Void

    var body: some View {
        HStack(spacing: 40) {
            // 拍摄按钮
            Button(action: onQARequest) {
                VStack {
                    Image(systemName: "question.circle.fill")
                        .font(.system(size: 32))
                    Text("问答")
                        .font(.caption)
                }
                .foregroundColor(.white)
            }

            // 拍照按钮
            Button(action: {}) {
                VStack {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 32))
                    Text("拍照")
                        .font(.caption)
                }
                .foregroundColor(.white)
            }

            // 设置按钮
            Button(action: {}) {
                VStack {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 32))
                    Text("设置")
                        .font(.caption)
                }
                .foregroundColor(.white)
            }
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 40)
        .background(Color.black.opacity(0.6))
        .cornerRadius(20)
    }
}

// MARK: - 相机预览

struct CameraPreviewView: View {
    var body: some View {
        Color.gray.opacity(0.3)
            .overlay(
                Text("相机预览")
                    .foregroundColor(.white)
            )
    }
}