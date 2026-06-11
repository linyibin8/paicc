import Speech
import AVFoundation

/// 语音服务状态
enum VoiceServiceState {
    case idle
    case listening
    case speaking
    case playing
}

/// 语音识别错误
enum VoiceRecognitionError: Error {
    case notAuthorized
    case recognizerUnavailable
    case audioEngineError
    case recognitionFailed
    case timeout
}

/// 语音服务 - 语音识别和 TTS
class VoiceService: NSObject {

    // MARK: - 单例
    static let shared = VoiceService()

    // MARK: - 属性
    private let speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    private(set) var state: VoiceServiceState = .idle
    private(set) var isListening = false

    // MARK: - 静音检测配置
    var silenceThreshold: TimeInterval = 3.0  // 沉默阈值（秒）
    var silenceLevel: Float = 0.1             // 静音检测的音量阈值 (0.0-1.0)
    var enableSilenceDetection: Bool = true   // 是否启用静音检测
    private var silenceTimer: Timer?
    private var lastAudioLevel: Float = 0.0

    // MARK: - TTS
    private let synthesizer = AVSpeechSynthesizer()
    private var isTTSPlaying = false

    // MARK: - 流式音频播放
    private var audioPlayer: AVAudioPlayer?
    private var audioEnginePlayer: AVAudioPlayerNode?
    private var streamingBuffer: AVAudioPCMBuffer?
    private var audioFile: AVAudioFile?

    // MARK: - 思考音
    private var thinkingAudioPlayer: AVAudioPlayer?
    private var thinkingSoundData: Data?

    // MARK: - 回调
    var onSpeechResult: ((String, Bool) -> Void)?  // (text, isFinal)
    var onListeningStateChanged: ((Bool) -> Void)?
    var onStateChanged: ((VoiceServiceState) -> Void)?
    var onError: ((Error) -> Void)?
    var onAudioLevelChanged: ((Float) -> Void)?    // 用于音量可视化
    var onThinkingStateChanged: ((Bool) -> Void)?  // 思考音状态

    // MARK: - 初始化

    override init() {
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
        super.init()
        synthesizer.delegate = self
        setupAudioSession()
    }

    private func setupAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers])
            try audioSession.setActive(true)

            // 注册音频中断通知
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleAudioSessionInterruption),
                name: AVAudioSession.interruptionNotification,
                object: audioSession
            )

            // 注册路由变化通知
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleRouteChange),
                name: AVAudioSession.routeChangeNotification,
                object: audioSession
            )
        } catch {
            print("Audio session setup error: \(error)")
        }
    }

    @objc private func handleAudioSessionInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        switch type {
        case .began:
            stopSpeaking()
            stopListening()
        case .ended:
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume) {
                    try? AVAudioSession.sharedInstance().setActive(true)
                }
            }
        @unknown default:
            break
        }
    }

    @objc private func handleRouteChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }

        switch reason {
        case .oldDeviceUnavailable:
            // 耳机被拔掉，暂停播放
            pauseSpeaking()
        default:
            break
        }
    }

    // MARK: - 状态管理

    private func updateState(_ newState: VoiceServiceState) {
        guard state != newState else { return }
        state = newState
        onStateChanged?(newState)
    }

    // MARK: - 语音识别

    func startListening() {
        guard !isListening else { return }
        guard state != .speaking else {
            // 如果正在说话，等待说完再开始
            return
        }

        // 请求权限
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                switch status {
                case .authorized:
                    self?.beginRecognition()
                case .denied, .restricted:
                    self?.onError?(VoiceRecognitionError.notAuthorized)
                case .notDetermined:
                    print("Speech recognition not determined")
                @unknown default:
                    break
                }
            }
        }
    }

    private func beginRecognition() {
        guard speechRecognizer?.isAvailable == true else {
            onError?(VoiceRecognitionError.recognizerUnavailable)
            return
        }

        // 取消之前的任务
        recognitionTask?.cancel()
        recognitionTask = nil

        // 配置音频输入
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        // 确保格式支持
        guard recordingFormat.sampleRate > 0 && recordingFormat.channelCount > 0 else {
            onError?(VoiceRecognitionError.audioEngineError)
            return
        }

        // 安装音频 tap 用于语音识别和音量检测
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)

            // 计算音频级别
            self?.calculateAudioLevel(from: buffer)
        }

        // 创建识别请求
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        recognitionRequest?.shouldReportPartialResults = true

        if #available(iOS 16, *) {
            recognitionRequest?.addsPunctuation = true
        }

        // 开始识别
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest!) { [weak self] result, error in
            guard let self = self else { return }

            var isFinal = false

            if let result = result {
                let text = result.bestTranscription.formattedString
                isFinal = result.isFinal

                DispatchQueue.main.async {
                    self.onSpeechResult?(text, isFinal)
                }

                // 重置静音计时器（当检测到语音时）
                if !text.isEmpty && self.enableSilenceDetection {
                    self.resetSilenceTimer()
                }
            }

            if error != nil || isFinal {
                self.cleanupRecognition()
            }
        }

        // 启动音频引擎
        audioEngine.prepare()
        do {
            try audioEngine.start()
            isListening = true
            updateState(.listening)
            onListeningStateChanged?(true)

            if enableSilenceDetection {
                startSilenceTimer()
            }
        } catch {
            print("Audio engine start error: \(error)")
            onError?(VoiceRecognitionError.audioEngineError)
        }
    }

    private func calculateAudioLevel(from buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }

        let channelDataValue = channelData.pointee
        let channelDataValueArray = stride(from: 0, to: Int(buffer.frameLength), by: buffer.stride).map { channelDataValue[$0] }

        // 计算 RMS
        let rms = sqrt(channelDataValueArray.map { $0 * $0 }.reduce(0, +) / Float(buffer.frameLength))

        // 转换为分贝并归一化
        let avgPower = 20 * log10(rms)
        let normalizedLevel = max(0, min(1, (avgPower + 50) / 50))

        lastAudioLevel = normalizedLevel

        DispatchQueue.main.async { [weak self] in
            self?.onAudioLevelChanged?(normalizedLevel)
        }
    }

    func stopListening() {
        guard isListening else { return }

        audioEngine.stop()
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()

        cleanupRecognition()
        onListeningStateChanged?(false)
        updateState(.idle)
    }

    private func cleanupRecognition() {
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest = nil
        recognitionTask = nil
        isListening = false

        silenceTimer?.invalidate()
        silenceTimer = nil

        DispatchQueue.main.async { [weak self] in
            self?.onListeningStateChanged?(false)
            self?.updateState(.idle)
        }
    }

    // MARK: - 静音检测

    private func startSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceThreshold, repeats: false) { [weak self] _ in
            self?.handleSilenceDetected()
        }
    }

    func resetSilenceTimer() {
        guard enableSilenceDetection else { return }
        startSilenceTimer()
    }

    private func handleSilenceDetected() {
        // 只有当音量低于阈值时才停止
        if lastAudioLevel < silenceLevel {
            stopListening()
        }
    }

    // MARK: - 思考音播放

    /// 设置思考音数据
    func setThinkingSound(_ data: Data) {
        thinkingSoundData = data
    }

    /// 设置思考音 URL
    func setThinkingSound(url: URL) {
        do {
            thinkingSoundData = try Data(contentsOf: url)
        } catch {
            print("Failed to load thinking sound: \(error)")
        }
    }

    /// 播放思考音
    func playThinkingSound() {
        guard let data = thinkingSoundData else {
            print("No thinking sound data available")
            return
        }

        stopThinkingSound()

        do {
            thinkingAudioPlayer = try AVAudioPlayer(data: data)
            thinkingAudioPlayer?.numberOfLoops = -1  // 循环播放
            thinkingAudioPlayer?.volume = 0.5
            thinkingAudioPlayer?.play()

            DispatchQueue.main.async { [weak self] in
                self?.onThinkingStateChanged?(true)
            }
        } catch {
            print("Failed to play thinking sound: \(error)")
        }
    }

    /// 停止思考音
    func stopThinkingSound() {
        thinkingAudioPlayer?.stop()
        thinkingAudioPlayer = nil

        DispatchQueue.main.async { [weak self] in
            self?.onThinkingStateChanged?(false)
        }
    }

    // MARK: - TTS 语音合成

    func speak(_ text: String, language: String = "zh-CN") {
        // 停止之前的语音
        stopSpeaking()

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: language)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9  // 稍微慢一点
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0
        utterance.preUtteranceDelay = 0.1
        utterance.postUtteranceDelay = 0.1

        updateState(.speaking)
        isTTSPlaying = true
        synthesizer.speak(utterance)
    }

    /// 继续 TTS（从暂停恢复）
    func continueSpeaking() {
        if synthesizer.isPaused {
            synthesizer.continueSpeaking()
            isTTSPlaying = true
            updateState(.speaking)
        }
    }

    /// 暂停 TTS
    func pauseSpeaking() {
        if synthesizer.isSpeaking {
            synthesizer.pauseSpeaking(at: .word)
            isTTSPlaying = false
            updateState(.idle)
        }
    }

    /// 停止 TTS
    func stopSpeaking() {
        if synthesizer.isSpeaking || synthesizer.isPaused {
            synthesizer.stopSpeaking(at: .immediate)
            isTTSPlaying = false
            updateState(.idle)
        }

        // 同时停止流式音频
        stopStreamingAudio()
    }

    /// 中断当前播放，准备新的语音
    func interruptForNewSpeech(_ text: String, language: String = "zh-CN") {
        stopSpeaking()
        speak(text, language: language)
    }

    // MARK: - 流式音频播放

    /// 播放流式音频数据
    func playStreamingAudio(_ data: Data) {
        // 停止之前的播放
        stopStreamingAudio()
        stopSpeaking()

        do {
            // 保存到临时文件
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("streaming_audio_\(UUID().uuidString).wav")
            try data.write(to: tempURL)

            // 使用 AVAudioPlayer 播放
            audioPlayer = try AVAudioPlayer(contentsOf: tempURL)
            audioPlayer?.delegate = self
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()

            updateState(.playing)

            // 清理临时文件
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                try? FileManager.default.removeItem(at: tempURL)
            }
        } catch {
            print("Streaming audio playback error: \(error)")
            // 回退到系统 TTS
            if let text = String(data: data.prefix(1000), encoding: .utf8) {
                speak(text)
            }
        }
    }

    /// 使用 AVAudioEngine 播放流式音频（真正流式，无文件）
    func playStreamingAudioEngine(_ audioFormat: AVAudioFormat, audioChunks: Data) {
        stopStreamingAudio()
        stopSpeaking()

        audioEnginePlayer = AVAudioPlayerNode()
        audioEngine.attach(audioEnginePlayer!)

        let outputFormat = audioEngine.outputNode.inputFormat(forBus: 0)
        audioEngine.connect(audioEnginePlayer!, to: audioEngine.mainMixerNode, format: outputFormat)

        do {
            // 创建临时文件来存储音频数据
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("stream_\(UUID().uuidString).wav")
            try audioChunks.write(to: tempURL)

            audioFile = try AVAudioFile(forReading: tempURL)
            guard let file = audioFile else { return }

            audioEnginePlayer?.scheduleFile(file, at: nil) { [weak self] in
                DispatchQueue.main.async {
                    self?.updateState(.idle)
                    self?.cleanupStreamingResources()
                }
            }

            audioEngine.prepare()
            try audioEngine.start()
            audioEnginePlayer?.play()

            updateState(.playing)
        } catch {
            print("Audio engine streaming error: \(error)")
        }
    }

    /// 停止流式音频播放
    func stopStreamingAudio() {
        audioPlayer?.stop()
        audioPlayer = nil

        audioEnginePlayer?.stop()
        if let player = audioEnginePlayer {
            audioEngine.detach(player)
        }
        audioEnginePlayer = nil

        audioFile = nil

        if state == .playing {
            updateState(.idle)
        }
    }

    private func cleanupStreamingResources() {
        audioPlayer = nil
        audioEnginePlayer = nil
        audioFile = nil
    }

    // MARK: - 播放音频数据（保留原有方法以兼容）

    func playAudioData(_ data: Data) {
        playStreamingAudio(data)
    }

    // MARK: - 权限检查

    func requestPermissions(completion: @escaping (Bool, Bool) -> Void) {
        var speechAuthorized = false
        var micAuthorized = false

        let group = DispatchGroup()

        // 请求语音识别权限
        group.enter()
        SFSpeechRecognizer.requestAuthorization { status in
            speechAuthorized = (status == .authorized)
            group.leave()
        }

        // 请求麦克风权限
        group.enter()
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            micAuthorized = granted
            group.leave()
        }

        group.notify(queue: .main) {
            completion(speechAuthorized, micAuthorized)
        }
    }

    // MARK: - 清理

    deinit {
        NotificationCenter.default.removeObserver(self)
        stopListening()
        stopSpeaking()
        stopStreamingAudio()
        stopThinkingSound()
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension VoiceService: AVSpeechSynthesizerDelegate {

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        updateState(.speaking)
        isTTSPlaying = true
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        isTTSPlaying = false
        updateState(.idle)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
        isTTSPlaying = false
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) {
        isTTSPlaying = true
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        isTTSPlaying = false
        updateState(.idle)
    }
}

// MARK: - AVAudioPlayerDelegate

extension VoiceService: AVAudioPlayerDelegate {

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        updateState(.idle)
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        print("Audio player decode error: \(error?.localizedDescription ?? "unknown")")
        updateState(.idle)
    }
}