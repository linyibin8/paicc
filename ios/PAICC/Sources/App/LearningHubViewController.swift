import UIKit
import SnapKit

// MARK: - 学习中心视图控制器

class LearningHubViewController: UIViewController {

    // MARK: - UI 组件
    private lazy var scrollView: UIScrollView = {
        let scroll = UIScrollView()
        scroll.alwaysBounceVertical = true
        return scroll
    }()

    private let contentView = UIView()

    private lazy var statsCard: UIView = {
        let card = UIView()
        card.backgroundColor = .systemBackground
        card.layer.cornerRadius = 16
        return card
    }()

    // MARK: - 生命周期

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        loadStats()
    }

    // MARK: - UI 设置

    private func setupUI() {
        title = "学习中心"
        view.backgroundColor = .systemGroupedBackground

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "完成",
            style: .done,
            target: self,
            action: #selector(dismissVC)
        )

        view.addSubview(scrollView)
        scrollView.addSubview(contentView)

        scrollView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        contentView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
            make.width.equalTo(scrollView)
        }

        // 添加功能卡片
        setupFeatureCards()
    }

    private func setupFeatureCards() {
        var lastView: UIView?

        // 学习概览卡片
        let overviewCard = createOverviewCard()
        contentView.addSubview(overviewCard)
        overviewCard.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(16)
            make.left.right.equalToSuperview().inset(16)
        }
        lastView = overviewCard

        // 功能按钮
        let features: [(String, String, String, UIColor)] = [
            ("错题管理", "edit.square.stack", "管理你的错题，标记掌握状态", .systemRed),
            ("复习队列", "clock.arrow.circlepath", "按照记忆曲线复习错题", .systemOrange),
            ("学习报告", "doc.text.magnifyingglass", "查看历史学习报告", .systemBlue),
            ("学习画像", "person.crop.circle.badge.chart", "了解你的学习特点", .systemPurple)
        ]

        for (title, icon, subtitle, color) in features {
            let card = createFeatureCard(title: title, icon: icon, subtitle: subtitle, color: color) { [weak self] in
                self?.openFeature(title)
            }
            contentView.addSubview(card)
            card.snp.makeConstraints { make in
                if let last = lastView {
                    make.top.equalTo(last.snp.bottom).offset(12)
                }
                make.left.right.equalToSuperview().inset(16)
            }
            lastView = card
        }

        lastView?.snp.makeConstraints { make in
            make.bottom.equalToSuperview().offset(-20)
        }
    }

    private func createOverviewCard() -> UIView {
        let card = UIView()
        card.backgroundColor = .systemBackground
        card.layer.cornerRadius = 16

        let titleLabel = UILabel()
        titleLabel.text = "📈 今日学习"
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        card.addSubview(titleLabel)

        let statsStack = UIStackView()
        statsStack.axis = .horizontal
        statsStack.distribution = .fillEqually
        card.addSubview(statsStack)

        titleLabel.snp.makeConstraints { make in
            make.top.left.right.equalToSuperview().inset(16)
        }

        statsStack.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(12)
            make.left.right.bottom.equalToSuperview().inset(16)
        }

        let stats: [(String, String, UIColor)] = [
            ("0", "会话", .systemBlue),
            ("0", "错题", .systemRed),
            ("0", "复习", .systemGreen)
        ]

        for (value, label, color) in stats {
            let statView = createStatView(value: value, label: label, color: color)
            statsStack.addArrangedSubview(statView)
        }

        return card
    }

    private func createStatView(value: String, label: String, color: UIColor) -> UIView {
        let container = UIView()

        let valueLabel = UILabel()
        valueLabel.text = value
        valueLabel.font = .systemFont(ofSize: 24, weight: .bold)
        valueLabel.textColor = color
        valueLabel.textAlignment = .center
        container.addSubview(valueLabel)

        let labelLabel = UILabel()
        labelLabel.text = label
        labelLabel.font = .systemFont(ofSize: 12)
        labelLabel.textColor = .secondaryLabel
        labelLabel.textAlignment = .center
        container.addSubview(labelLabel)

        valueLabel.snp.makeConstraints { make in
            make.top.centerX.equalToSuperview()
        }

        labelLabel.snp.makeConstraints { make in
            make.top.equalTo(valueLabel.snp.bottom).offset(4)
            make.centerX.bottom.equalToSuperview()
        }

        return container
    }

    private func createFeatureCard(title: String, icon: String, subtitle: String, color: UIColor, action: @escaping () -> Void) -> UIView {
        let card = UIView()
        card.backgroundColor = .systemBackground
        card.layer.cornerRadius = 12

        let iconView = UIImageView(image: UIImage(systemName: icon))
        iconView.tintColor = color
        iconView.contentMode = .scaleAspectFit
        card.addSubview(iconView)

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 16, weight: .medium)
        card.addSubview(titleLabel)

        let subtitleLabel = UILabel()
        subtitleLabel.text = subtitle
        subtitleLabel.font = .systemFont(ofSize: 13)
        subtitleLabel.textColor = .secondaryLabel
        card.addSubview(subtitleLabel)

        let arrowView = UIImageView(image: UIImage(systemName: "chevron.right"))
        arrowView.tintColor = .tertiaryLabel
        card.addSubview(arrowView)

        iconView.snp.makeConstraints { make in
            make.left.equalToSuperview().offset(16)
            make.centerY.equalToSuperview()
            make.size.equalTo(32)
        }

        titleLabel.snp.makeConstraints { make in
            make.left.equalTo(iconView.snp.right).offset(12)
            make.top.equalToSuperview().offset(16)
            make.right.equalTo(arrowView.snp.left).offset(-12)
        }

        subtitleLabel.snp.makeConstraints { make in
            make.left.equalTo(titleLabel)
            make.top.equalTo(titleLabel.snp.bottom).offset(4)
            make.right.equalTo(titleLabel)
            make.bottom.equalToSuperview().offset(-16)
        }

        arrowView.snp.makeConstraints { make in
            make.right.equalToSuperview().offset(-16)
            make.centerY.equalToSuperview()
            make.size.equalTo(16)
        }

        let tap = UITapGestureRecognizer(target: self, action: #selector(featureCardTapped))
        card.addGestureRecognizer(tap)
        card.tag = title.hashValue
        card.isUserInteractionEnabled = true

        // 存储闭包
        objc_setAssociatedObject(card, &AssociatedKeys.action, action, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

        return card
    }

    @objc private func featureCardTapped(_ gesture: UITapGestureRecognizer) {
        if let view = gesture.view,
           let action = objc_getAssociatedObject(view, &AssociatedKeys.action) as? () -> Void {
            action()
        }
    }

    private func openFeature(_ title: String) {
        let vc: UIViewController
        switch title {
        case "错题管理":
            vc = MistakeListViewController()
        case "复习队列":
            vc = ReviewQueueViewController()
        case "学习报告":
            vc = SessionListViewController()
        case "学习画像":
            vc = StudentProfileViewController()
        default:
            return
        }
        navigationController?.pushViewController(vc, animated: true)
    }

    private func loadStats() {
        // TODO: 加载实际统计数据
    }

    @objc private func dismissVC() {
        dismiss(animated: true)
    }
}

// MARK: - 学习报告列表视图控制器

class SessionListViewController: UIViewController {

    private lazy var tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .insetGrouped)
        table.delegate = self
        table.dataSource = self
        table.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
        return table
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "学习报告"
        view.backgroundColor = .systemGroupedBackground

        view.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }
}

extension SessionListViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return 0
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        return UITableViewCell()
    }
}

// MARK: - 关联键

private struct AssociatedKeys {
    static var action = "actionKey"
}