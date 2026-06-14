import UIKit
import SnapKit

// MARK: - 错题状态
enum MistakeStatus: String, CaseIterable {
    case suspected = "suspected"
    case confirmed = "confirmed"
    case ignored = "ignored"
    case corrected = "corrected"
    case mastered = "mastered"

    var displayName: String {
        switch self {
        case .suspected: return "疑似错题"
        case .confirmed: return "确认错题"
        case .ignored: return "已忽略"
        case .corrected: return "已订正"
        case .mastered: return "已掌握"
        }
    }

    var color: UIColor {
        switch self {
        case .suspected: return .systemOrange
        case .confirmed: return .systemRed
        case .ignored: return .systemGray
        case .corrected: return .systemBlue
        case .mastered: return .systemGreen
        }
    }
}

// MARK: - 错题列表视图控制器

class MistakeListViewController: UIViewController {

    // MARK: - UI 组件
    private lazy var tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .insetGrouped)
        table.delegate = self
        table.dataSource = self
        table.register(MistakeCell.self, forCellReuseIdentifier: MistakeCell.identifier)
        table.backgroundColor = .systemGroupedBackground
        return table
    }()

    private lazy var segmentedControl: UISegmentedControl = {
        let items = MistakeStatus.allCases.map { $0.displayName }
        let segment = UISegmentedControl(items: items)
        segment.selectedSegmentIndex = 0
        segment.addTarget(self, action: #selector(filterChanged), for: .valueChanged)
        return segment
    }()

    private lazy var emptyLabel: UILabel = {
        let label = UILabel()
        label.text = "暂无错题记录\n开始学习后会自动记录"
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
    private var mistakes: [MistakeItem] = []
    private var filteredMistakes: [MistakeItem] = []
    private var selectedStatus: MistakeStatus = .suspected

    // MARK: - 生命周期

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        loadMistakes()
    }

    // MARK: - UI 设置

    private func setupUI() {
        title = "错题管理"
        view.backgroundColor = .systemGroupedBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "chart.bar"),
            style: .plain,
            target: self,
            action: #selector(showStats)
        )

        let headerView = UIView(frame: CGRect(x: 0, y: 0, width: view.bounds.width, height: 50))
        headerView.addSubview(segmentedControl)
        segmentedControl.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.left.right.equalToSuperview().inset(16)
        }
        tableView.tableHeaderView = headerView

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

    private func loadMistakes() {
        Task {
            do {
                let response = try await APIClient.shared.fetchMistakes(studentId: "default")
                await MainActor.run {
                    self.mistakes = response
                    self.applyFilter()
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
        loadMistakes()
    }

    private func applyFilter() {
        filteredMistakes = mistakes.filter { $0.status == selectedStatus.rawValue }
        tableView.reloadData()
        emptyLabel.isHidden = !filteredMistakes.isEmpty
    }

    @objc private func filterChanged() {
        selectedStatus = MistakeStatus.allCases[segmentedControl.selectedSegmentIndex]
        applyFilter()
    }

    // MARK: - 操作

    @objc private func showStats() {
        let statsVC = MistakeStatsViewController()
        navigationController?.pushViewController(statsVC, animated: true)
    }

    private func updateMistakeStatus(_ mistake: MistakeItem, newStatus: MistakeStatus) {
        Task {
            do {
                try await APIClient.shared.updateMistake(
                    mistakeId: mistake.mistake_id,
                    status: newStatus.rawValue
                )
                await MainActor.run {
                    self.loadMistakes()
                }
            } catch {
                await MainActor.run {
                    self.showError("更新失败: \(error.localizedDescription)")
                }
            }
        }
    }

    private func showError(_ message: String) {
        let alert = UIAlertController(title: "错误", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - UITableViewDataSource

extension MistakeListViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return filteredMistakes.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: MistakeCell.identifier, for: indexPath) as! MistakeCell
        let mistake = filteredMistakes[indexPath.row]
        cell.configure(with: mistake)
        return cell
    }
}

// MARK: - UITableViewDelegate

extension MistakeListViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let mistake = filteredMistakes[indexPath.row]
        let detailVC = MistakeDetailViewController(mistake: mistake)
        detailVC.onStatusChanged = { [weak self] newStatus in
            self?.updateMistakeStatus(mistake, newStatus: newStatus)
        }
        navigationController?.pushViewController(detailVC, animated: true)
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let mistake = filteredMistakes[indexPath.row]

        let confirmAction = UIContextualAction(style: .normal, title: "确认") { [weak self] _, _, completion in
            self?.updateMistakeStatus(mistake, newStatus: .confirmed)
            completion(true)
        }
        confirmAction.backgroundColor = .systemRed

        let ignoreAction = UIContextualAction(style: .destructive, title: "忽略") { [weak self] _, _, completion in
            self?.updateMistakeStatus(mistake, newStatus: .ignored)
            completion(true)
        }

        return UISwipeActionsConfiguration(actions: [ignoreAction, confirmAction])
    }
}

// MARK: - 错题单元格

class MistakeCell: UITableViewCell {
    static let identifier = "MistakeCell"

    private let questionLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 15, weight: .medium)
        label.numberOfLines = 2
        return label
    }()

    private let subjectLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabel
        return label
    }()

    private let statusBadge: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textAlignment = .center
        label.layer.cornerRadius = 8
        label.clipsToBounds = true
        return label
    }()

    private let reviewCountLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 11)
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
        contentView.addSubview(questionLabel)
        contentView.addSubview(subjectLabel)
        contentView.addSubview(statusBadge)
        contentView.addSubview(reviewCountLabel)

        questionLabel.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(12)
            make.left.equalToSuperview().offset(16)
            make.right.equalTo(statusBadge.snp.left).offset(-8)
        }

        subjectLabel.snp.makeConstraints { make in
            make.top.equalTo(questionLabel.snp.bottom).offset(4)
            make.left.equalToSuperview().offset(16)
            make.bottom.equalToSuperview().offset(-12)
        }

        statusBadge.snp.makeConstraints { make in
            make.right.equalToSuperview().offset(-16)
            make.centerY.equalToSuperview()
            make.width.greaterThanOrEqualTo(60)
            make.height.equalTo(24)
        }

        reviewCountLabel.snp.makeConstraints { make in
            make.right.equalToSuperview().offset(-16)
            make.bottom.equalToSuperview().offset(-8)
        }
    }

    func configure(with mistake: MistakeItem) {
        questionLabel.text = mistake.questionText
        subjectLabel.text = mistake.subject ?? "未知科目"
        reviewCountLabel.text = "复习 \(mistake.reviewCount) 次"

        let status = MistakeStatus(rawValue: mistake.status) ?? .suspected
        statusBadge.text = "  \(status.displayName)  "
        statusBadge.backgroundColor = status.color.withAlphaComponent(0.2)
        statusBadge.textColor = status.color
    }
}

// MARK: - 错题详情视图控制器

class MistakeDetailViewController: UIViewController {
    private let mistake: MistakeItem
    var onStatusChanged: ((MistakeStatus) -> Void)?

    private let scrollView = UIScrollView()
    private let contentView = UIView()

    init(mistake: MistakeItem) {
        self.mistake = mistake
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }

    private func setupUI() {
        title = "错题详情"
        view.backgroundColor = .systemGroupedBackground

        view.addSubview(scrollView)
        scrollView.addSubview(contentView)

        scrollView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        contentView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
            make.width.equalTo(scrollView)
        }

        let status = MistakeStatus(rawValue: mistake.status) ?? .suspected

        // 题目
        addSection(title: "题目", content: mistake.questionText)

        // 学生答案
        if let studentAnswer = mistake.student_answer {
            addSection(title: "学生答案", content: studentAnswer)
        }

        // 正确答案
        if let correctAnswer = mistake.correct_answer {
            addSection(title: "正确答案", content: correctAnswer, isHighlighted: true)
        }

        // 错误类型
        if let errorType = mistake.error_type {
            addSection(title: "错误类型", content: errorType)
        }

        // 复习次数
        addInfoRow(title: "复习次数", value: "\(mistake.reviewCount) 次")

        // 操作按钮
        let buttonStack = UIStackView()
        buttonStack.axis = .horizontal
        buttonStack.distribution = .fillEqually
        buttonStack.spacing = 12
        contentView.addSubview(buttonStack)

        buttonStack.snp.makeConstraints { make in
            make.top.equalTo(contentView.subviews.last!.snp.bottom).offset(20)
            make.left.right.equalToSuperview().inset(16)
            make.bottom.equalToSuperview().offset(-20)
            make.height.equalTo(44)
        }

        let actions: [(String, MistakeStatus, UIColor)] = [
            ("确认错题", .confirmed, .systemRed),
            ("已订正", .corrected, .systemBlue),
            ("已掌握", .mastered, .systemGreen)
        ]

        for (title, status, color) in actions {
            let button = UIButton(type: .system)
            button.setTitle(title, for: .normal)
            button.backgroundColor = color
            button.setTitleColor(.white, for: .normal)
            button.layer.cornerRadius = 8
            button.addAction(UIAction { [weak self] _ in
                self?.onStatusChanged?(status)
                self?.navigationController?.popViewController(animated: true)
            }, for: .touchUpInside)
            buttonStack.addArrangedSubview(button)
        }
    }

    private var lastSectionView: UIView?

    private func addSection(title: String, content: String, isHighlighted: Bool = false) {
        let container = UIView()
        container.backgroundColor = .systemBackground
        container.layer.cornerRadius = 12
        contentView.addSubview(container)

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.textColor = .secondaryLabel
        container.addSubview(titleLabel)

        let contentLabel = UILabel()
        contentLabel.text = content
        contentLabel.font = .systemFont(ofSize: 15)
        contentLabel.numberOfLines = 0
        if isHighlighted {
            contentLabel.textColor = .systemGreen
        }
        container.addSubview(contentLabel)

        titleLabel.snp.makeConstraints { make in
            make.top.left.right.equalToSuperview().inset(12)
        }

        contentLabel.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(6)
            make.left.right.bottom.equalToSuperview().inset(12)
        }

        if let last = lastSectionView {
            container.snp.makeConstraints { make in
                make.top.equalTo(last.snp.bottom).offset(12)
                make.left.right.equalToSuperview().inset(16)
            }
        } else {
            container.snp.makeConstraints { make in
                make.top.equalToSuperview().offset(16)
                make.left.right.equalToSuperview().inset(16)
            }
        }

        lastSectionView = container
    }

    private func addInfoRow(title: String, value: String) {
        let container = UIView()
        container.backgroundColor = .systemBackground
        container.layer.cornerRadius = 12
        contentView.addSubview(container)

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 15)
        container.addSubview(titleLabel)

        let valueLabel = UILabel()
        valueLabel.text = value
        valueLabel.font = .systemFont(ofSize: 15)
        valueLabel.textColor = .secondaryLabel
        container.addSubview(valueLabel)

        titleLabel.snp.makeConstraints { make in
            make.left.equalToSuperview().offset(16)
            make.centerY.equalToSuperview()
        }

        valueLabel.snp.makeConstraints { make in
            make.right.equalToSuperview().offset(-16)
            make.centerY.equalToSuperview()
        }

        container.snp.makeConstraints { make in
            make.height.equalTo(50)
            if let last = lastSectionView {
                make.top.equalTo(last.snp.bottom).offset(12)
                make.left.right.equalToSuperview().inset(16)
            } else {
                make.top.equalToSuperview().offset(16)
                make.left.right.equalToSuperview().inset(16)
            }
        }

        lastSectionView = container
    }
}

// MARK: - 错题统计视图控制器

class MistakeStatsViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "错题统计"
        view.backgroundColor = .systemGroupedBackground

        let label = UILabel()
        label.text = "统计功能开发中"
        label.textColor = .secondaryLabel
        view.addSubview(label)
        label.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }
    }
}