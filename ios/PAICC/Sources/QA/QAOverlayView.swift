import UIKit

/// QA 问答浮层视图 - 显示问答状态和响应内容
class QAOverlayView: UIView {

    // MARK: - UI 组件

    private lazy var containerView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.85)
        view.layer.cornerRadius = 20
        return view
    }()

    lazy var statusIconLabel: UILabel = {
        let label = UILabel()
        label.text = "🔍"
        label.font = .systemFont(ofSize: 32)
        label.textAlignment = .center
        return label
    }()

    lazy var statusLabel: UILabel = {
        let label = UILabel()
        label.text = "扫描中..."
        label.textColor = .white
        label.font = .systemFont(ofSize: 18, weight: .medium)
        label.textAlignment = .center
        return label
    }()

    lazy var answerLabel: UILabel = {
        let label = UILabel()
        label.text = ""
        label.textColor = .white
        label.font = .systemFont(ofSize: 16)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.isHidden = true
        return label
    }()

    // 思考中动画视图
    lazy var thinkingContainerView: UIView = {
        let view = UIView()
        view.isHidden = true
        return view
    }()

    lazy var thinkingDot1: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.white.withAlphaComponent(0.9)
        view.layer.cornerRadius = 5
        return view
    }()

    lazy var thinkingDot2: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.white.withAlphaComponent(0.7)
        view.layer.cornerRadius = 5
        return view
    }()

    lazy var thinkingDot3: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.white.withAlphaComponent(0.5)
        view.layer.cornerRadius = 5
        return view
    }()

    lazy var hintLabel: UILabel = {
        let label = UILabel()
        label.text = "👌 打断  |  ✌️ 结束"
        label.textColor = UIColor.white.withAlphaComponent(0.6)
        label.font = .systemFont(ofSize: 12)
        label.textAlignment = .center
        return label
    }()

    // 流式文本相关
    lazy var streamingCursor: UILabel = {
        let label = UILabel()
        label.text = "▋"
        label.textColor = UIColor.white.withAlphaComponent(0.8)
        label.font = .systemFont(ofSize: 16)
        label.isHidden = true
        return label
    }()

    // 进度条
    lazy var progressContainerView: UIView = {
        let view = UIView()
        view.isHidden = true
        return view
    }()

    lazy var progressTrackView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.white.withAlphaComponent(0.2)
        view.layer.cornerRadius = 2
        return view
    }()

    lazy var progressBarView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.systemBlue
        view.layer.cornerRadius = 2
        return view
    }()

    lazy var progressTimeLabel: UILabel = {
        let label = UILabel()
        label.text = "15s"
        label.textColor = UIColor.white.withAlphaComponent(0.7)
        label.font = .systemFont(ofSize: 11)
        label.textAlignment = .right
        return label
    }()

    // MARK: - 状态

    enum QAState {
        case idle           // 空闲
        case scanning       // 扫描中
        case pointing       // 指向中
        case capturing      // 采集中
        case listening      // 等待语音输入
        case thinking       // AI 思考中
        case speaking       // TTS 播报中
    }

    var state: QAState = .idle {
        didSet {
            animateStateTransition()
        }
    }

    // MARK: - 流式文本状态

    private var streamingTimer: Timer?
    private var streamingText: String = ""
    private var streamingIndex: Int = 0
    var typingSpeed: TimeInterval = 0.03 // 打字速度（秒/字）

    // MARK: - 进度条状态

    private var progressTimer: Timer?
    private var progressDuration: TimeInterval = 15.0
    private var progressRemaining: TimeInterval = 15.0

    // MARK: - 初始化

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
        setupObservers()
        setupCursorAnimation()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - UI 设置

    private func setupUI() {
        addSubview(containerView)
        containerView.addSubview(statusIconLabel)
        containerView.addSubview(statusLabel)
        containerView.addSubview(answerLabel)
        containerView.addSubview(streamingCursor)
        containerView.addSubview(thinkingContainerView)
        containerView.addSubview(hintLabel)
        containerView.addSubview(progressContainerView)

        // 思考动画容器
        thinkingContainerView.addSubview(thinkingDot1)
        thinkingContainerView.addSubview(thinkingDot2)
        thinkingContainerView.addSubview(thinkingDot3)

        // 进度条容器
        progressContainerView.addSubview(progressTrackView)
        progressContainerView.addSubview(progressBarView)
        progressContainerView.addSubview(progressTimeLabel)

        // 设置约束
        setupConstraints()

        // 默认隐藏
        isHidden = true
    }

    private func setupConstraints() {
        containerView.translatesAutoresizingMaskIntoConstraints = false
        statusIconLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        answerLabel.translatesAutoresizingMaskIntoConstraints = false
        streamingCursor.translatesAutoresizingMaskIntoConstraints = false
        thinkingContainerView.translatesAutoresizingMaskIntoConstraints = false
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        progressContainerView.translatesAutoresizingMaskIntoConstraints = false
        progressTrackView.translatesAutoresizingMaskIntoConstraints = false
        progressBarView.translatesAutoresizingMaskIntoConstraints = false
        progressTimeLabel.translatesAutoresizingMaskIntoConstraints = false
        thinkingDot1.translatesAutoresizingMaskIntoConstraints = false
        thinkingDot2.translatesAutoresizingMaskIntoConstraints = false
        thinkingDot3.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            // 容器
            containerView.centerXAnchor.constraint(equalTo: centerXAnchor),
            containerView.centerYAnchor.constraint(equalTo: centerYAnchor),
            containerView.widthAnchor.constraint(equalToConstant: 280),
            containerView.heightAnchor.constraint(greaterThanOrEqualToConstant: 200),

            // 状态图标
            statusIconLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 30),
            statusIconLabel.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            statusIconLabel.widthAnchor.constraint(equalToConstant: 60),
            statusIconLabel.heightAnchor.constraint(equalToConstant: 60),

            // 思考动画容器
            thinkingContainerView.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            thinkingContainerView.centerYAnchor.constraint(equalTo: statusIconLabel.centerYAnchor),
            thinkingContainerView.widthAnchor.constraint(equalToConstant: 60),
            thinkingContainerView.heightAnchor.constraint(equalToConstant: 20),

            // 思考动画点
            thinkingDot1.centerYAnchor.constraint(equalTo: thinkingContainerView.centerYAnchor),
            thinkingDot1.trailingAnchor.constraint(equalTo: thinkingContainerView.centerXAnchor, constant: -15),
            thinkingDot1.widthAnchor.constraint(equalToConstant: 10),
            thinkingDot1.heightAnchor.constraint(equalToConstant: 10),

            thinkingDot2.centerYAnchor.constraint(equalTo: thinkingContainerView.centerYAnchor),
            thinkingDot2.centerXAnchor.constraint(equalTo: thinkingContainerView.centerXAnchor),
            thinkingDot2.widthAnchor.constraint(equalToConstant: 10),
            thinkingDot2.heightAnchor.constraint(equalToConstant: 10),

            thinkingDot3.centerYAnchor.constraint(equalTo: thinkingContainerView.centerYAnchor),
            thinkingDot3.leadingAnchor.constraint(equalTo: thinkingContainerView.centerXAnchor, constant: 15),
            thinkingDot3.widthAnchor.constraint(equalToConstant: 10),
            thinkingDot3.heightAnchor.constraint(equalToConstant: 10),

            // 状态标签
            statusLabel.topAnchor.constraint(equalTo: statusIconLabel.bottomAnchor, constant: 16),
            statusLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 20),
            statusLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -20),

            // 答案标签
            answerLabel.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 12),
            answerLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 20),
            answerLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -20),

            // 光标
            streamingCursor.leadingAnchor.constraint(equalTo: answerLabel.trailingAnchor, constant: 2),
            streamingCursor.bottomAnchor.constraint(equalTo: answerLabel.bottomAnchor, constant: -2),

            // 进度条容器
            progressContainerView.topAnchor.constraint(equalTo: answerLabel.bottomAnchor, constant: 12),
            progressContainerView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 20),
            progressContainerView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -20),
            progressContainerView.heightAnchor.constraint(equalToConstant: 16),

            // 进度条轨道
            progressTrackView.leadingAnchor.constraint(equalTo: progressContainerView.leadingAnchor),
            progressTrackView.trailingAnchor.constraint(equalTo: progressTimeLabel.leadingAnchor, constant: -8),
            progressTrackView.centerYAnchor.constraint(equalTo: progressContainerView.centerYAnchor),
            progressTrackView.heightAnchor.constraint(equalToConstant: 4),

            // 进度条填充
            progressBarView.leadingAnchor.constraint(equalTo: progressTrackView.leadingAnchor),
            progressBarView.topAnchor.constraint(equalTo: progressTrackView.topAnchor),
            progressBarView.bottomAnchor.constraint(equalTo: progressTrackView.bottomAnchor),
            progressBarView.widthAnchor.constraint(equalTo: progressTrackView.widthAnchor),

            // 时间标签
            progressTimeLabel.trailingAnchor.constraint(equalTo: progressContainerView.trailingAnchor),
            progressTimeLabel.centerYAnchor.constraint(equalTo: progressContainerView.centerYAnchor),
            progressTimeLabel.widthAnchor.constraint(equalToConstant: 24),

            // 提示标签
            hintLabel.topAnchor.constraint(equalTo: progressContainerView.bottomAnchor, constant: 12),
            hintLabel.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            hintLabel.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -20)
        ])
    }

    private func setupObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleQAStateChanged(_:)),
            name: .qaStateChanged,
            object: nil
        )
    }

    private func setupCursorAnimation() {
        // 光标闪烁动画
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self, self.streamingCursor.isHidden == false else { return }
            UIView.animate(withDuration: 0.25) {
                self.streamingCursor.alpha = self.streamingCursor.alpha == 1.0 ? 0.0 : 1.0
            }
        }
    }

    // MARK: - 状态更新

    @objc private func handleQAStateChanged(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let stateValue = notification.userInfo?["state"] as? String else { return }
            self?.updateState(from: stateValue)
        }
    }

    private func updateState(from stateString: String) {
        switch stateString {
        case "idle":
            state = .idle
        case "scanning":
            state = .scanning
        case "pointing":
            state = .pointing
        case "capturing":
            state = .capturing
        case "listening":
            state = .listening
        case "thinking":
            state = .thinking
        case "speaking":
            state = .speaking
        default:
            state = .idle
        }
    }

    // MARK: - 状态切换动画

    func animateStateTransition() {
        // 停止之前的动画
        stopThinkingAnimation()
        stopProgressAnimation()

        // 根据状态更新 UI
        switch state {
        case .idle:
            showIdleState()
        case .scanning:
            showScanningState()
        case .pointing:
            showPointingState()
        case .capturing:
            showCapturingState()
        case .listening:
            showListeningState()
        case .thinking:
            showThinkingState()
        case .speaking:
            showSpeakingState()
        }
    }

    func showIdleState() {
        UIView.animate(withDuration: 0.3) {
            self.statusIconLabel.alpha = 1
            self.statusIconLabel.text = "🔍"
            self.statusLabel.text = "扫描中..."
            self.statusLabel.alpha = 1
            self.answerLabel.isHidden = true
            self.streamingCursor.isHidden = true
            self.thinkingContainerView.isHidden = true
            self.hintLabel.alpha = 0
            self.progressContainerView.isHidden = true
        }
    }

    func showInterruptedState() {
        UIView.animate(withDuration: 0.3) {
            self.statusIconLabel.alpha = 1
            self.statusIconLabel.text = "✋"
            self.statusLabel.text = "已打断，请继续..."
            self.statusLabel.alpha = 1
            self.answerLabel.isHidden = true
            self.streamingCursor.isHidden = true
            self.thinkingContainerView.isHidden = true
            self.hintLabel.alpha = 1
            self.progressContainerView.isHidden = true
        }
        stopAllAnimations()
    }

    func showScanningState() {
        UIView.animate(withDuration: 0.3) {
            self.statusIconLabel.alpha = 1
            self.statusIconLabel.text = "🔍"
            self.statusLabel.text = "扫描画面..."
            self.statusLabel.alpha = 1
            self.answerLabel.isHidden = true
            self.streamingCursor.isHidden = true
            self.thinkingContainerView.isHidden = true
            self.hintLabel.alpha = 1
            self.progressContainerView.isHidden = true
        }

        // 扫描图标脉冲动画
        animatePulse(on: statusIconLabel)
    }

    func showPointingState() {
        UIView.animate(withDuration: 0.3) {
            self.statusIconLabel.alpha = 1
            self.statusIconLabel.text = "👆"
            self.statusLabel.text = "指向中..."
            self.statusLabel.alpha = 1
            self.answerLabel.isHidden = true
            self.streamingCursor.isHidden = true
            self.thinkingContainerView.isHidden = true
            self.hintLabel.alpha = 1
            self.progressContainerView.isHidden = true
        }
    }

    func showCapturingState() {
        UIView.animate(withDuration: 0.3) {
            self.statusIconLabel.alpha = 1
            self.statusIconLabel.text = "📷"
            self.statusLabel.text = "采集中..."
            self.statusLabel.alpha = 1
            self.answerLabel.isHidden = true
            self.streamingCursor.isHidden = true
            self.thinkingContainerView.isHidden = true
            self.hintLabel.alpha = 1
            self.progressContainerView.isHidden = true
        }
    }

    func showListeningState() {
        UIView.animate(withDuration: 0.3) {
            self.statusIconLabel.alpha = 1
            self.statusIconLabel.text = "🎤"
            self.statusLabel.text = "请说..."
            self.statusLabel.alpha = 1
            self.answerLabel.isHidden = true
            self.streamingCursor.isHidden = true
            self.thinkingContainerView.isHidden = true
            self.hintLabel.alpha = 1
            self.progressContainerView.isHidden = true
        }

        // 麦克风呼吸动画
        animateBreathing(on: statusIconLabel)
    }

    func showThinkingState() {
        UIView.animate(withDuration: 0.3) {
            self.statusIconLabel.alpha = 0
            self.statusLabel.text = "思考中..."
            self.statusLabel.alpha = 1
            self.answerLabel.isHidden = true
            self.streamingCursor.isHidden = true
            self.thinkingContainerView.isHidden = false
            self.hintLabel.alpha = 1
            self.progressContainerView.isHidden = true
        }

        // 开始思考动画
        startThinkingAnimation()
    }

    func showSpeakingState() {
        UIView.animate(withDuration: 0.3) {
            self.statusIconLabel.alpha = 1
            self.statusIconLabel.text = "🔊"
            self.statusLabel.text = "回答中..."
            self.statusLabel.alpha = 1
            self.answerLabel.isHidden = false
            self.streamingCursor.isHidden = false
            self.thinkingContainerView.isHidden = true
            self.hintLabel.alpha = 1
            self.progressContainerView.isHidden = false
        }

        // 开始进度条动画
        startProgressAnimation()
    }

    // MARK: - 思考中动画

    private func startThinkingAnimation() {
        // 三点波浪动画
        animateThinkingDot(thinkingDot1, delay: 0.0)
        animateThinkingDot(thinkingDot2, delay: 0.15)
        animateThinkingDot(thinkingDot3, delay: 0.30)
    }

    func animateThinkingDot(_ dot: UIView, delay: TimeInterval) {
        UIView.animate(
            withDuration: 0.6,
            delay: delay,
            options: [.repeat, .autoreverse, .curveEaseInOut],
            animations: {
                dot.transform = CGAffineTransform(translationX: 0, y: -8)
                dot.alpha = 1.0
            },
            completion: nil
        )
    }

    func stopThinkingAnimation() {
        [thinkingDot1, thinkingDot2, thinkingDot3].forEach { dot in
            dot.layer.removeAllAnimations()
            dot.transform = .identity
            dot.alpha = 1.0
        }
    }

    // MARK: - 脉冲动画

    func animatePulse(on view: UIView) {
        view.layer.removeAnimation(forKey: "pulse")

        let pulse = CABasicAnimation(keyPath: "transform.scale")
        pulse.duration = 1.0
        pulse.fromValue = 1.0
        pulse.toValue = 1.15
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

        view.layer.add(pulse, forKey: "pulse")
    }

    // MARK: - 呼吸动画

    func animateBreathing(on view: UIView) {
        view.layer.removeAnimation(forKey: "breathing")

        let breathing = CABasicAnimation(keyPath: "opacity")
        breathing.duration = 1.5
        breathing.fromValue = 1.0
        breathing.toValue = 0.5
        breathing.autoreverses = true
        breathing.repeatCount = .infinity
        breathing.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

        view.layer.add(breathing, forKey: "breathing")
    }

    // MARK: - 进度条动画

    private func startProgressAnimation() {
        progressRemaining = progressDuration
        updateProgressUI()

        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.progressRemaining -= 0.1

            if self.progressRemaining <= 0 {
                self.stopProgressAnimation()
            } else {
                self.updateProgressUI()
            }
        }
    }

    func stopProgressAnimation() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    private func updateProgressUI() {
        let progress = CGFloat(progressRemaining / progressDuration)

        // 更新进度条宽度
        progressBarView.constraints.forEach { constraint in
            if constraint.firstAttribute == .width {
                constraint.isActive = false
            }
        }

        let widthConstraint = progressBarView.widthAnchor.constraint(
            equalTo: progressTrackView.widthAnchor,
            multiplier: progress
        )
        widthConstraint.isActive = true

        // 更新时间标签
        progressTimeLabel.text = "\(Int(ceil(progressRemaining)))s"

        // 根据剩余时间更新进度条颜色
        if progressRemaining <= 5 {
            progressBarView.backgroundColor = UIColor.systemOrange
        } else if progressRemaining <= 3 {
            progressBarView.backgroundColor = UIColor.systemRed
        } else {
            progressBarView.backgroundColor = UIColor.systemBlue
        }
    }

    // MARK: - 流式文本显示（打字机效果）

    /// 显示完整答案（无打字机效果）
    /// - Parameter text: 答案文本
    func showAnswer(_ text: String) {
        DispatchQueue.main.async { [weak self] in
            self?.stopTypingAnimation()
            self?.answerLabel.text = text
            self?.answerLabel.isHidden = false
            self?.streamingCursor.isHidden = true
        }
    }

    /// 显示流式响应（打字机效果）
    /// - Parameters:
    ///   - text: 完整答案文本
    ///   - speed: 打字速度（秒/字），默认 0.03
    func showTypingAnswer(_ text: String, speed: TimeInterval = 0.03) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            self.stopTypingAnimation()

            self.streamingText = text
            self.streamingIndex = 0
            self.typingSpeed = speed
            self.answerLabel.text = ""
            self.answerLabel.isHidden = false
            self.streamingCursor.isHidden = false

            self.startTypingAnimation()
        }
    }

    private func startTypingAnimation() {
        streamingTimer = Timer.scheduledTimer(withTimeInterval: typingSpeed, repeats: true) { [weak self] _ in
            guard let self = self else { return }

            if self.streamingIndex < self.streamingText.count {
                let index = self.streamingText.index(self.streamingText.startIndex, offsetBy: self.streamingIndex)
                self.answerLabel.text = String(self.streamingText.prefix(self.streamingIndex + 1))
                self.streamingIndex += 1
            } else {
                self.stopTypingAnimation()
                self.streamingCursor.isHidden = true
            }
        }
    }

    func stopTypingAnimation() {
        streamingTimer?.invalidate()
        streamingTimer = nil
        streamingText = ""
        streamingIndex = 0
    }

    /// 显示流式响应（实时更新，逐字追加）
    /// - Parameter text: 部分答案文本
    func showStreamingAnswer(_ text: String) {
        DispatchQueue.main.async { [weak self] in
            self?.answerLabel.text = text
            self?.answerLabel.isHidden = false
            self?.streamingCursor.isHidden = false
            self?.layoutIfNeeded()
        }
    }

    /// 完成流式响应
    func finishStreamingAnswer() {
        DispatchQueue.main.async { [weak self] in
            self?.stopTypingAnimation()
            self?.streamingCursor.isHidden = true
        }
    }

    // MARK: - 显示和隐藏

    /// 显示浮层
    func show() {
        isHidden = false
        alpha = 0

        UIView.animate(withDuration: 0.3) {
            self.alpha = 1
        }
    }

    /// 显示浮层（带自动消失）
    /// - Parameter duration: 自动消失时间，默认 15 秒
    func showWithAutoDismiss(duration: TimeInterval = 15.0) {
        show()
        progressDuration = duration
        progressRemaining = duration

        // 取消之前的定时器
        stopProgressAnimation()

        // 设置新的定时器
        progressTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            self?.dismiss()
        }
    }

    /// 取消自动消失
    func cancelAutoDismiss() {
        stopProgressAnimation()
    }

    /// 隐藏浮层
    func dismiss() {
        stopAllAnimations()

        UIView.animate(withDuration: 0.3) {
            self.alpha = 0
        } completion: { [weak self] _ in
            self?.isHidden = true
            self?.resetState()
        }
    }

    /// 重置状态
    private func resetState() {
        stopTypingAnimation()
        stopProgressAnimation()
        stopThinkingAnimation()

        answerLabel.text = ""
        answerLabel.isHidden = true
        streamingCursor.isHidden = true
        statusIconLabel.alpha = 1
        statusIconLabel.layer.removeAllAnimations()
        thinkingContainerView.isHidden = true
        progressContainerView.isHidden = true
    }

    /// 停止所有动画
    func stopAllAnimations() {
        stopTypingAnimation()
        stopProgressAnimation()
        stopThinkingAnimation()
        statusIconLabel.layer.removeAllAnimations()
    }

    // MARK: - 析构

    deinit {
        stopAllAnimations()
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - Notification Extension

// 注意: Notification.Name 扩展已在 AppState.swift 中定义
