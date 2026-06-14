import UIKit
import SnapKit

// MARK: - 复习队列视图控制器

class ReviewQueueViewController: UIViewController {

    // MARK: - UI 组件
    private lazy var tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .insetGrouped)
        table.delegate = self
        table.dataSource = self
        table.register(ReviewQueueCell.self, forCellReuseIdentifier: ReviewQueueCell.identifier)
        table.backgroundColor = .systemGroupedBackground
        return table
    }()

    private lazy var emptyLabel: UILabel = {
        let label = UILabel()
        label.text = "暂无待复习内容\n恭喜你完成所有复习！"
        label.textColor = .secondaryLabel
        label.font = .systemFont(ofSize: 16)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.isHidden = true
        return label
    }()

    private lazy var refreshControl: UIRefreshControl = {
        let control = UIRefreshControl()
        control.addTarget(self, action: #selector(refreshData), for: .valueChanged)
        return control
    }()

    // MARK: - 数据
    private var reviewItems: [ReviewQueueItem] = []

    // MARK: - 生命周期

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        loadReviewQueue()
    }

    // MARK: - UI 设置

    private func setupUI() {
        title = "复习队列"
        view.backgroundColor = .systemGroupedBackground

        view.addSubview(tableView)
        view.addSubview(emptyLabel)

        tableView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        emptyLabel.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }

        tableView.refreshControl = refreshControl
    }

    // MARK: - 数据加载

    private func loadReviewQueue() {
        Task {
            do {
                let response = try await APIClient.shared.fetchReviewQueue(studentId: "default")
                await MainActor.run {
                    self.reviewItems = response.items
                    self.tableView.reloadData()
                    self.emptyLabel.isHidden = !response.items.isEmpty
                    self.refreshControl.endRefreshing()
                }
            } catch {
                await MainActor.run {
                    self.refreshControl.endRefreshing()
                    self.showError("加载失败: \(error.localizedDescription)")
                }
            }
        }
    }

    @objc private func refreshData() {
        loadReviewQueue()
    }

    private func showError(_ message: String) {
        let alert = UIAlertController(title: "错误", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - UITableViewDataSource

extension ReviewQueueViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return reviewItems.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: ReviewQueueCell.identifier, for: indexPath) as! ReviewQueueCell
        let item = reviewItems[indexPath.row]
        cell.configure(with: item)
        return cell
    }
}

// MARK: - UITableViewDelegate

extension ReviewQueueViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let item = reviewItems[indexPath.row]
        showReviewSheet(for: item)
    }

    private func showReviewSheet(for item: ReviewQueueItem) {
        let alert = UIAlertController(
            title: "复习评分",
            message: "这道题你掌握得怎么样？",
            preferredStyle: .actionSheet
        )

        let ratings: [(String, Int)] = [
            ("完全忘记 (0)", 0),
            ("模糊记得 (2)", 2),
            ("有点困难 (3)", 3),
            ("顺利回忆 (4)", 4),
            ("完全掌握 (5)", 5)
        ]

        for (title, quality) in ratings {
            alert.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                self?.submitReview(item: item, quality: quality)
            })
        }

        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(alert, animated: true)
    }

    private func submitReview(item: ReviewQueueItem, quality: Int) {
        Task {
            do {
                let response = try await APIClient.shared.submitReview(queueId: item.queueId, quality: quality)
                await MainActor.run {
                    if response.isMastered {
                        self.showMessage("🎉 恭喜掌握这道题！")
                    } else {
                        let days = response.newInterval
                        self.showMessage("复习成功！\(days)天后再来复习")
                    }
                    self.loadReviewQueue()
                }
            } catch {
                await MainActor.run {
                    self.showError("提交失败: \(error.localizedDescription)")
                }
            }
        }
    }

    private func showMessage(_ message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - 复习单元格

class ReviewQueueCell: UITableViewCell {
    static let identifier = "ReviewQueueCell"

    private let questionLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 15, weight: .medium)
        label.numberOfLines = 2
        return label
    }()

    private let difficultyLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabel
        return label
    }()

    private let intervalLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12)
        label.textColor = .tertiaryLabel
        return label
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        accessoryType = .disclosureIndicator

        contentView.addSubview(questionLabel)
        contentView.addSubview(difficultyLabel)
        contentView.addSubview(intervalLabel)

        questionLabel.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(12)
            make.left.equalToSuperview().offset(16)
            make.right.equalToSuperview().offset(-40)
        }

        difficultyLabel.snp.makeConstraints { make in
            make.top.equalTo(questionLabel.snp.bottom).offset(6)
            make.left.equalToSuperview().offset(16)
            make.bottom.equalToSuperview().offset(-12)
        }

        intervalLabel.snp.makeConstraints { make in
            make.centerY.equalTo(difficultyLabel)
            make.left.equalTo(difficultyLabel.snp.right).offset(16)
        }
    }

    func configure(with item: ReviewQueueItem) {
        questionLabel.text = item.questionText

        let difficultyText: String
        if item.difficulty < 0.3 {
            difficultyText = "简单"
        } else if item.difficulty < 0.7 {
            difficultyText = "中等"
        } else {
            difficultyText = "困难"
        }
        difficultyLabel.text = "难度: \(difficultyText) | 已复习\(item.repetitions)次"

        intervalLabel.text = "间隔\(item.interval)天"
    }
}

// MARK: - 学生画像视图控制器

class StudentProfileViewController: UIViewController {

    // MARK: - UI 组件
    private lazy var scrollView: UIScrollView = {
        let scroll = UIScrollView()
        scroll.alwaysBounceVertical = true
        return scroll
    }()

    private let contentView = UIView()

    private lazy var refreshControl: UIRefreshControl = {
        let control = UIRefreshControl()
        control.addTarget(self, action: #selector(refreshData), for: .valueChanged)
        return control
    }()

    // MARK: - 数据
    private var stats: StudentStats?
    private var profile: StudentProfile?

    // MARK: - 生命周期

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        loadData()
    }

    // MARK: - UI 设置

    private func setupUI() {
        title = "学习画像"
        view.backgroundColor = .systemGroupedBackground

        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        scrollView.refreshControl = refreshControl

        scrollView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        contentView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
            make.width.equalTo(scrollView)
        }
    }

    // MARK: - 数据加载

    private func loadData() {
        Task {
            do {
                async let statsTask = APIClient.shared.fetchStudentStats(studentId: "default")
                async let profileTask = APIClient.shared.fetchStudentProfile(studentId: "default")

                let (statsResult, profileResult) = try await (statsTask, profileTask)

                await MainActor.run {
                    self.stats = statsResult
                    self.profile = profileResult
                    self.refreshControl.endRefreshing()
                    self.updateUI()
                }
            } catch {
                await MainActor.run {
                    self.refreshControl.endRefreshing()
                }
            }
        }
    }

    @objc private func refreshData() {
        loadData()
    }

    private func updateUI() {
        contentView.subviews.forEach { $0.removeFromSuperview() }

        var lastView: UIView?

        // 学习概览卡片
        if let stats = stats {
            let overviewCard = createOverviewCard(stats: stats)
            contentView.addSubview(overviewCard)
            overviewCard.snp.makeConstraints { make in
                make.top.equalToSuperview().offset(16)
                make.left.right.equalToSuperview().inset(16)
            }
            lastView = overviewCard
        }

        // 薄弱知识点
        if let profile = profile, !profile.weakTopics.isEmpty {
            let weakCard = createTopicCard(title: "薄弱知识点", topics: profile.weakTopics, color: .systemRed)
            contentView.addSubview(weakCard)
            weakCard.snp.makeConstraints { make in
                if let last = lastView {
                    make.top.equalTo(last.snp.bottom).offset(16)
                } else {
                    make.top.equalToSuperview().offset(16)
                }
                make.left.right.equalToSuperview().inset(16)
            }
            lastView = weakCard
        }

        // 已掌握知识点
        if let profile = profile, !profile.masteredTopics.isEmpty {
            let masteredCard = createTopicCard(title: "已掌握知识点", topics: profile.masteredTopics, color: .systemGreen)
            contentView.addSubview(masteredCard)
            masteredCard.snp.makeConstraints { make in
                if let last = lastView {
                    make.top.equalTo(last.snp.bottom).offset(16)
                } else {
                    make.top.equalToSuperview().offset(16)
                }
                make.left.right.equalToSuperview().inset(16)
            }
            lastView = masteredCard
        }

        if let last = lastView {
            last.snp.makeConstraints { make in
                make.bottom.equalToSuperview().offset(-20)
            }
        }
    }

    private func createOverviewCard(stats: StudentStats) -> UIView {
        let card = UIView()
        card.backgroundColor = .systemBackground
        card.layer.cornerRadius = 12

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        card.addSubview(stack)
        stack.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(16)
        }

        // 标题
        let titleLabel = UILabel()
        titleLabel.text = "📊 学习概览"
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        stack.addArrangedSubview(titleLabel)

        // 统计项
        let items: [(String, String)] = [
            ("📚 学习会话", "\(stats.totalSessions) 次"),
            ("❌ 错题总数", "\(stats.totalMistakes) 道"),
            ("✅ 正确率", String(format: "%.1f%%", stats.accuracyRate)),
            ("🌟 已掌握", "\(stats.masteredCount) 道"),
            ("🔥 连续学习", "\(stats.streakDays) 天")
        ]

        for (emoji, value) in items {
            let row = createStatRow(emoji: emoji, value: value)
            stack.addArrangedSubview(row)
        }

        return card
    }

    private func createStatRow(emoji: String, value: String) -> UIView {
        let row = UIView()

        let emojiLabel = UILabel()
        emojiLabel.text = emoji
        emojiLabel.font = .systemFont(ofSize: 14)
        row.addSubview(emojiLabel)

        let valueLabel = UILabel()
        valueLabel.text = value
        valueLabel.font = .systemFont(ofSize: 15)
        valueLabel.textAlignment = .right
        row.addSubview(valueLabel)

        emojiLabel.snp.makeConstraints { make in
            make.left.centerY.equalToSuperview()
        }

        valueLabel.snp.makeConstraints { make in
            make.right.centerY.equalToSuperview()
        }

        row.snp.makeConstraints { make in
            make.height.equalTo(30)
        }

        return row
    }

    private func createTopicCard(title: String, topics: [String], color: UIColor) -> UIView {
        let card = UIView()
        card.backgroundColor = .systemBackground
        card.layer.cornerRadius = 12

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 8
        card.addSubview(stack)
        stack.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(16)
        }

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textColor = color
        stack.addArrangedSubview(titleLabel)

        for topic in topics.prefix(5) {
            let tag = UILabel()
            tag.text = "• \(topic)"
            tag.font = .systemFont(ofSize: 14)
            tag.textColor = .secondaryLabel
            stack.addArrangedSubview(tag)
        }

        return card
    }
}