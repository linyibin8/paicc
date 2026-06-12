import UIKit

/// QA 问答浮层视图
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
        label.text = "🎤"
        label.font = .systemFont(ofSize: 32)
        label.textAlignment = .center
        return label
    }()

    private lazy var statusLabel: UILabel = {
        let label = UILabel()
        label.text = "请说..."
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

    // MARK: - 状态

    enum QAState {
        case listening      // 等待语音输入
        case thinking       // AI 思考中
        case speaking       // TTS 播报中
        case idle           // 空闲
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
        containerView.addSubview(thinkingView)
        containerView.addSubview(hintLabel)

        containerView.translatesAutoresizingMaskIntoConstraints = false
        statusIcon.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        answerLabel.translatesAutoresizingMaskIntoConstraints = false
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

            hintLabel.topAnchor.constraint(equalTo: answerLabel.bottomAnchor, constant: 16),
            hintLabel.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            hintLabel.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -20)
        ])

        // 默认显示
        state = .idle
    }

    private func updateUI() {
        DispatchQueue.main.async {
            switch self.state {
            case .idle:
                self.statusIcon.text = "🔍"
                self.statusIcon.isHidden = false
                self.statusLabel.text = "扫描中..."
                self.answerLabel.isHidden = true
                self.thinkingView.stopAnimating()

            case .listening:
                self.statusIcon.text = "🎤"
                self.statusIcon.isHidden = false
                self.statusLabel.text = "请说..."
                self.answerLabel.isHidden = true
                self.thinkingView.stopAnimating()

            case .thinking:
                self.statusIcon.isHidden = true
                self.statusLabel.text = "思考中..."
                self.answerLabel.isHidden = true
                self.thinkingView.startAnimating()

            case .speaking:
                self.statusIcon.text = "🔊"
                self.statusIcon.isHidden = false
                self.statusLabel.text = "回答中..."
                self.answerLabel.isHidden = false
                self.thinkingView.stopAnimating()
            }
        }
    }

    // MARK: - 观察者

    private func setupObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleQAStateChanged(_:)),
            name: .qaStateChanged,
            object: nil
        )
    }

    @objc private func handleQAStateChanged(_ notification: Notification) {
        if let stateString = notification.userInfo?["state"] as? String {
            switch stateString {
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
    }

    // MARK: - 显示答案

    func showAnswer(_ text: String) {
        DispatchQueue.main.async {
            self.answerLabel.text = text
            self.answerLabel.isHidden = false
        }
    }

    // MARK: - 自动消失

    func showWithAutoDismiss(duration: TimeInterval = 15.0) {
        isHidden = false
        alpha = 0

        UIView.animate(withDuration: 0.3) {
            self.alpha = 1
        }

        // 15秒后自动消失
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            self?.dismiss()
        }
    }

    func dismiss() {
        UIView.animate(withDuration: 0.3) {
            self.alpha = 0
        } completion: { _ in
            self.isHidden = true
        }
    }
}