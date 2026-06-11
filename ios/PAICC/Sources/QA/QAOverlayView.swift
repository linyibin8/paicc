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

    private lazy var statusIcon: UILabel = {
        let label = UILabel()
        label.text = "🔍"
        label.font = .systemFont(ofSize: 32)
        label.textAlignment = .center
        return label
    }()

    private lazy var statusLabel: UILabel = {
        let label = UILabel()
        label.text = "扫描中..."
        label.textColor = .white
        label.font = .systemFont(ofSize: 18, weight: .medium)
        label.textAlignment = .center
        return label
    }()

    private lazy var answerLabel: UILabel = {
        let label = UILabel()
        label.text = ""
        label.textColor = .white
        label.font = .systemFont(ofSize: 16)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.isHidden = true
        return label
    }()

    private lazy var thinkingView: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.color = .white
        indicator.hidesWhenStopped = true
        return indicator
    }()

    private lazy var hintLabel: UILabel = {
        let label = UILabel()
        label.text = "👌 打断  |  ✌️ 结束"
        label.textColor = UIColor.white.withAlphaComponent(0.6)
        label.font = .systemFont(ofSize: 12)
        label.textAlignment = .center
        return label
    }()

    private lazy var streamingCursor: UILabel = {
        let label = UILabel()
        label.text = "▋"
        label.textColor = UIColor.white.withAlphaComponent(0.8)
        label.font = .systemFont(ofSize: 16)
        label.isHidden = true
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
            updateUI()
        }
    }

    // MARK: - 初始化

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
        setupObservers()
        setupStreamingAnimation()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - UI 设置

    private func setupUI() {
        addSubview(containerView)
        containerView.addSubview(statusIcon)
        containerView.addSubview(statusLabel)
        containerView.addSubview(answerLabel)
        containerView.addSubview(streamingCursor)
        containerView.addSubview(thinkingView)
        containerView.addSubview(hintLabel)

        containerView.translatesAutoresizingMaskIntoConstraints = false
        statusIcon.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        answerLabel.translatesAutoresizingMaskIntoConstraints = false
        streamingCursor.translatesAutoresizingMaskIntoConstraints = false
        thinkingView.translatesAutoresizingMaskIntoConstraints = false
        hintLabel.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            containerView.centerXAnchor.constraint(equalTo: centerXAnchor),
            containerView.centerYAnchor.constraint(equalTo: centerYAnchor),
            containerView.widthAnchor.constraint(equalToConstant: 280),
            containerView.heightAnchor.constraint(greaterThanOrEqualToConstant: 200),

            statusIcon.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 30),
            statusIcon.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            statusIcon.widthAnchor.constraint(equalToConstant: 60),
            statusIcon.heightAnchor.constraint(equalToConstant: 60),

            thinkingView.centerXAnchor.constraint(equalTo: statusIcon.centerXAnchor),
            thinkingView.centerYAnchor.constraint(equalTo: statusIcon.centerYAnchor),

            statusLabel.topAnchor.constraint(equalTo: statusIcon.bottomAnchor, constant: 16),
            statusLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 20),
            statusLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -20),

            answerLabel.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 12),
            answerLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 20),
            answerLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -20),

            streamingCursor.leadingAnchor.constraint(equalTo: answerLabel.trailingAnchor, constant: 2),
            streamingCursor.bottomAnchor.constraint(equalTo: answerLabel.bottomAnchor, constant: -2),

            hintLabel.topAnchor.constraint(equalTo: answerLabel.bottomAnchor, constant: 16),
            hintLabel.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            hintLabel.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -20)
        ])

        // 默认隐藏
        isHidden = true
    }

    private func setupObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleQAStateChanged(_:)),
            name: .qaStateChanged,
            object: nil
        )
    }

    private func setupStreamingAnimation() {
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

    private func updateUI() {
        switch state {
        case .idle:
            statusIcon.text = "🔍"
            statusIcon.isHidden = false
            statusLabel.text = "扫描中..."
            answerLabel.isHidden = true
            streamingCursor.isHidden = true
            thinkingView.stopAnimating()
            hintLabel.isHidden = true

        case .scanning:
            statusIcon.text = "🔍"
            statusIcon.isHidden = false
            statusLabel.text = "扫描画面..."
            answerLabel.isHidden = true
            streamingCursor.isHidden = true
            thinkingView.stopAnimating()
            hintLabel.isHidden = false

        case .pointing:
            statusIcon.text = "👆"
            statusIcon.isHidden = false
            statusLabel.text = "指向中..."
            answerLabel.isHidden = true
            streamingCursor.isHidden = true
            thinkingView.stopAnimating()
            hintLabel.isHidden = false

        case .capturing:
            statusIcon.text = "📷"
            statusIcon.isHidden = false
            statusLabel.text = "采集中..."
            answerLabel.isHidden = true
            streamingCursor.isHidden = true
            thinkingView.stopAnimating()
            hintLabel.isHidden = false

        case .listening:
            statusIcon.text = "🎤"
            statusIcon.isHidden = false
            statusLabel.text = "请说..."
            answerLabel.isHidden = true
            streamingCursor.isHidden = true
            thinkingView.stopAnimating()
            hintLabel.isHidden = false

        case .thinking:
            statusIcon.isHidden = true
            statusLabel.text = "思考中..."
            answerLabel.isHidden = true
            streamingCursor.isHidden = true
            thinkingView.startAnimating()
            hintLabel.isHidden = false

        case .speaking:
            statusIcon.text = "🔊"
            statusIcon.isHidden = false
            statusLabel.text = "回答中..."
            answerLabel.isHidden = false
            streamingCursor.isHidden = true
            thinkingView.stopAnimating()
            hintLabel.isHidden = false
        }
    }

    // MARK: - 显示答案

    /// 显示完整答案
    /// - Parameter text: 答案文本
    func showAnswer(_ text: String) {
        DispatchQueue.main.async { [weak self] in
            self?.answerLabel.text = text
            self?.answerLabel.isHidden = false
            self?.streamingCursor.isHidden = true
        }
    }

    /// 显示流式响应（实时更新）
    /// - Parameter text: 部分答案文本
    func showStreamingAnswer(_ text: String) {
        DispatchQueue.main.async { [weak self] in
            self?.answerLabel.text = text
            self?.answerLabel.isHidden = false
            self?.streamingCursor.isHidden = false

            // 自动滚动到底部
            self?.layoutIfNeeded()
        }
    }

    /// 完成流式响应
    func finishStreamingAnswer() {
        DispatchQueue.main.async { [weak self] in
            self?.streamingCursor.isHidden = true
        }
    }

    // MARK: - 显示和隐藏

    /// 显示浮层（带自动消失）
    /// - Parameter duration: 自动消失时间，默认 15 秒
    func showWithAutoDismiss(duration: TimeInterval = 15.0) {
        isHidden = false
        alpha = 0

        UIView.animate(withDuration: 0.3) {
            self.alpha = 1
        }

        // 取消之前的定时器
        autoDismissTimer?.invalidate()

        // 设置新的定时器
        autoDismissTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            self?.dismiss()
        }
    }

    /// 取消自动消失
    func cancelAutoDismiss() {
        autoDismissTimer?.invalidate()
        autoDismissTimer = nil
    }

    /// 隐藏浮层
    func dismiss() {
        UIView.animate(withDuration: 0.3) {
            self.alpha = 0
        } completion: { [weak self] _ in
            self?.isHidden = true
            self?.resetState()
        }
    }

    private var autoDismissTimer: Timer?

    private func resetState() {
        answerLabel.text = ""
        answerLabel.isHidden = true
        streamingCursor.isHidden = true
        thinkingView.stopAnimating()
        cancelAutoDismiss()
    }

    // MARK: - 析构

    deinit {
        autoDismissTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - Notification Extension

extension Notification.Name {
    static let qaStateChanged = Notification.Name("qaStateChanged")
}