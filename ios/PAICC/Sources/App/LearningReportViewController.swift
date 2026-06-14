import UIKit

/// 学习报告视图控制器
class LearningReportViewController: UIViewController {

    // MARK: - 数据

    private var sessionId: String?

    // MARK: - UI 组件

    private lazy var scrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.backgroundColor = .systemBackground
        return sv
    }()

    private lazy var contentView: UIView = {
        let view = UIView()
        return view
    }()

    private lazy var headerLabel: UILabel = {
        let label = UILabel()
        label.text = "📊 学习报告"
        label.font = .systemFont(ofSize: 24, weight: .bold)
        label.textAlignment = .center
        return label
    }()

    private lazy var summaryCard: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.1)
        view.layer.cornerRadius = 12
        return view
    }()

    private lazy var summaryLabel: UILabel = {
        let label = UILabel()
        label.text = "加载中..."
        label.font = .systemFont(ofSize: 16)
        label.numberOfLines = 0
        return label
    }()

    private lazy var mistakesSection: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.systemRed.withAlphaComponent(0.1)
        view.layer.cornerRadius = 12
        return view
    }()

    private lazy var mistakesTitleLabel: UILabel = {
        let label = UILabel()
        label.text = "❌ 错题候选"
        label.font = .systemFont(ofSize: 18, weight: .semibold)
        return label
    }()

    private lazy var mistakesTableView: UITableView = {
        let tv = UITableView()
        tv.register(UITableViewCell.self, forCellReuseIdentifier: "MistakeCell")
        tv.dataSource = self
        tv.delegate = self
        tv.isScrollEnabled = false
        return tv
    }()

    private lazy var knowledgeSection: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.1)
        view.layer.cornerRadius = 12
        return view
    }()

    private lazy var knowledgeTitleLabel: UILabel = {
        let label = UILabel()
        label.text = "📚 知识点清单"
        label.font = .systemFont(ofSize: 18, weight: .semibold)
        return label
    }()

    private lazy var knowledgeLabel: UILabel = {
        let label = UILabel()
        label.text = "暂无数据"
        label.font = .systemFont(ofSize: 14)
        label.numberOfLines = 0
        return label
    }()

    private var mistakes: [MistakeItem] = []

    // MARK: - 初始化

    convenience init(sessionId: String) {
        self.init()
        self.sessionId = sessionId
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        loadReport()
    }

    // MARK: - UI 设置

    private func setupUI() {
        title = "学习报告"
        view.backgroundColor = .systemBackground

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(dismissView)
        )

        view.addSubview(scrollView)
        scrollView.addSubview(contentView)

        contentView.addSubview(headerLabel)
        contentView.addSubview(summaryCard)
        summaryCard.addSubview(summaryLabel)
        contentView.addSubview(mistakesSection)
        mistakesSection.addSubview(mistakesTitleLabel)
        mistakesSection.addSubview(mistakesTableView)
        contentView.addSubview(knowledgeSection)
        knowledgeSection.addSubview(knowledgeTitleLabel)
        knowledgeSection.addSubview(knowledgeLabel)

        setupConstraints()
    }

    private func setupConstraints() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentView.translatesAutoresizingMaskIntoConstraints = false
        headerLabel.translatesAutoresizingMaskIntoConstraints = false
        summaryCard.translatesAutoresizingMaskIntoConstraints = false
        summaryLabel.translatesAutoresizingMaskIntoConstraints = false
        mistakesSection.translatesAutoresizingMaskIntoConstraints = false
        mistakesTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        mistakesTableView.translatesAutoresizingMaskIntoConstraints = false
        knowledgeSection.translatesAutoresizingMaskIntoConstraints = false
        knowledgeTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        knowledgeLabel.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),

            headerLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            headerLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),

            summaryCard.topAnchor.constraint(equalTo: headerLabel.bottomAnchor, constant: 20),
            summaryCard.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            summaryCard.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            summaryLabel.topAnchor.constraint(equalTo: summaryCard.topAnchor, constant: 16),
            summaryLabel.leadingAnchor.constraint(equalTo: summaryCard.leadingAnchor, constant: 16),
            summaryLabel.trailingAnchor.constraint(equalTo: summaryCard.trailingAnchor, constant: -16),
            summaryLabel.bottomAnchor.constraint(equalTo: summaryCard.bottomAnchor, constant: -16),

            mistakesSection.topAnchor.constraint(equalTo: summaryCard.bottomAnchor, constant: 16),
            mistakesSection.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            mistakesSection.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            mistakesTitleLabel.topAnchor.constraint(equalTo: mistakesSection.topAnchor, constant: 16),
            mistakesTitleLabel.leadingAnchor.constraint(equalTo: mistakesSection.leadingAnchor, constant: 16),

            mistakesTableView.topAnchor.constraint(equalTo: mistakesTitleLabel.bottomAnchor, constant: 8),
            mistakesTableView.leadingAnchor.constraint(equalTo: mistakesSection.leadingAnchor),
            mistakesTableView.trailingAnchor.constraint(equalTo: mistakesSection.trailingAnchor),
            mistakesTableView.heightAnchor.constraint(equalToConstant: 200),
            mistakesTableView.bottomAnchor.constraint(equalTo: mistakesSection.bottomAnchor, constant: -16),

            knowledgeSection.topAnchor.constraint(equalTo: mistakesSection.bottomAnchor, constant: 16),
            knowledgeSection.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            knowledgeSection.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            knowledgeSection.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20),

            knowledgeTitleLabel.topAnchor.constraint(equalTo: knowledgeSection.topAnchor, constant: 16),
            knowledgeTitleLabel.leadingAnchor.constraint(equalTo: knowledgeSection.leadingAnchor, constant: 16),

            knowledgeLabel.topAnchor.constraint(equalTo: knowledgeTitleLabel.bottomAnchor, constant: 8),
            knowledgeLabel.leadingAnchor.constraint(equalTo: knowledgeSection.leadingAnchor, constant: 16),
            knowledgeLabel.trailingAnchor.constraint(equalTo: knowledgeSection.trailingAnchor, constant: -16),
            knowledgeLabel.bottomAnchor.constraint(equalTo: knowledgeSection.bottomAnchor, constant: -16)
        ])
    }

    // MARK: - 数据加载

    private func loadReport() {
        guard let sessionId = sessionId else { return }

        Task {
            do {
                // 获取会话详情
                let session = try await APIClient.shared.getSession(sessionId: sessionId)

                await MainActor.run {
                    summaryLabel.text = session.summary ?? "暂无报告内容"
                }

                // 获取错题列表
                let mistakesResponse = try await APIClient.shared.getMistakes(sessionId: sessionId)
                await MainActor.run {
                    self.mistakes = mistakesResponse
                    self.mistakesTableView.reloadData()
                }

            } catch {
                await MainActor.run {
                    summaryLabel.text = "加载失败: \(error.localizedDescription)"
                }
            }
        }
    }

    @objc private func dismissView() {
        dismiss(animated: true)
    }
}

// MARK: - UITableViewDataSource & Delegate

extension LearningReportViewController: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return mistakes.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "MistakeCell", for: indexPath)
        let mistake = mistakes[indexPath.row]

        var config = cell.defaultContentConfiguration()
        config.text = mistake.question ?? "第 \(indexPath.row + 1) 题"
        config.secondaryText = mistake.status ?? "待确认"
        cell.contentConfiguration = config

        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        let mistake = mistakes[indexPath.row]
        showMistakeActions(mistake: mistake)
    }

    private func showMistakeActions(mistake: MistakeItem) {
        let alert = UIAlertController(title: "错题操作", message: mistake.question, preferredStyle: .actionSheet)

        alert.addAction(UIAlertAction(title: "✅ 确认错题", style: .default) { [weak self] _ in
            self?.updateMistakeStatus(mistake, status: "confirmed")
        })

        alert.addAction(UIAlertAction(title: "🗑️ 忽略", style: .default) { [weak self] _ in
            self?.updateMistakeStatus(mistake, status: "ignored")
        })

        alert.addAction(UIAlertAction(title: "✏️ 已订正", style: .default) { [weak self] _ in
            self?.updateMistakeStatus(mistake, status: "corrected")
        })

        alert.addAction(UIAlertAction(title: "🌟 已掌握", style: .default) { [weak self] _ in
            self?.updateMistakeStatus(mistake, status: "mastered")
        })

        alert.addAction(UIAlertAction(title: "取消", style: .cancel))

        present(alert, animated: true)
    }

    private func updateMistakeStatus(_ mistake: MistakeItem, status: String) {
        Task {
            do {
                try await APIClient.shared.updateMistake(mistakeId: mistake.id, status: status)
                await MainActor.run {
                    loadReport()
                }
            } catch {
                // 显示错误
            }
        }
    }
}

// MARK: - 错题数据模型

struct MistakeItem: Codable {
    let id: String
    let question: String?
    let status: String?
    let knowledge: String?
    let correction: String?
}
