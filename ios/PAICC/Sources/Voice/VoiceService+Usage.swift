import Foundation

/// 语音服务使用示例
///
/// ## 基本用法
///
/// ```swift
/// // 初始化并设置回调
/// let voiceService = VoiceService.shared
///
/// voiceService.onSpeechResult = { text, isFinal in
///     print("识别结果: \(text)")
///     if isFinal {
///         print("最终结果")
///     }
/// }
///
/// voiceService.onListeningStateChanged = { isListening in
///     print("监听状态: \(isListening)")
/// }
///
/// voiceService.onStateChanged = { state in
///     switch state {
///     case .idle: print("空闲")
///     case .listening: print("监听中")
///     case .speaking: print("说话中")
///     case .playing: print("播放中")
///     }
/// }
///
/// voiceService.onError = { error in
///     print("错误: \(error)")
/// }
///
/// // 开始语音识别
/// voiceService.startListening()
///
/// // 停止语音识别
/// voiceService.stopListening()
/// ```
///
/// ## TTS 语音合成
///
/// ```swift
/// // 播放 TTS
/// voiceService.speak("你好，我是 PAI-CC")
///
/// // 暂停 TTS
/// voiceService.pauseSpeaking()
///
/// // 继续 TTS
/// voiceService.continueSpeaking()
///
/// // 停止 TTS
/// voiceService.stopSpeaking()
///
/// // 中断并播放新内容
/// voiceService.interruptForNewSpeech("新的内容")
/// ```
///
/// ## 静音检测配置
///
/// ```swift
/// // 设置静音检测参数
/// voiceService.silenceThreshold = 3.0   // 3秒静音自动结束
/// voiceService.silenceLevel = 0.1       // 音量阈值 (0.0-1.0)
/// voiceService.enableSilenceDetection = true  // 启用静音检测
///
/// // 重置静音计时器（在检测到语音时调用）
/// voiceService.resetSilenceTimer()
/// ```
///
/// ## 思考音功能
///
/// ```swift
/// // 设置思考音数据
/// if let url = Bundle.main.url(forResource: "thinking", withExtension: "wav") {
///     voiceService.setThinkingSound(url: url)
/// }
///
/// // 或者使用 Data
/// voiceService.setThinkingSound(thinkingData)
///
/// // 播放思考音
/// voiceService.playThinkingSound()
///
/// // 监听思考音状态
/// voiceService.onThinkingStateChanged = { isPlaying in
///     print("思考音状态: \(isPlaying)")
/// }
///
/// // 停止思考音
/// voiceService.stopThinkingSound()
/// ```
///
/// ## 流式音频播放
///
/// ```swift
/// // 播放流式音频数据
/// voiceService.playStreamingAudio(audioData)
///
/// // 使用 AVAudioEngine 播放流式音频
/// let format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
/// voiceService.playStreamingAudioEngine(format, audioChunks: chunkData)
///
/// // 停止流式音频
/// voiceService.stopStreamingAudio()
/// ```
///
/// ## 权限请求
///
/// ```swift
/// voiceService.requestPermissions { speechAuthorized, micAuthorized in
///     if speechAuthorized && micAuthorized {
///         print("所有权限已获取")
///     } else {
///         print("缺少权限: speech=\(speechAuthorized), mic=\(micAuthorized)")
///     }
/// }
/// ```
///
/// ## 音量可视化
///
/// ```swift
/// voiceService.onAudioLevelChanged = { level in
///     // level 范围 0.0 - 1.0
///     DispatchQueue.main.async {
///         self.volumeLevelView.level = level
///     }
/// }
/// ```