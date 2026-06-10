import UIKit

/// 主视图控制器
class MainViewController: UIViewController {

    // MARK: - UI 组件
    private lazy var cameraPreviewView: UIView = {
        let view = UIView()
        view.backgroundColor = .black
        return view
    }()

    private lazy var statusLabel: UILabel = {
        let label = UILabel()
        label.text = "扫描中..."
        label.textColor = .white
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textAlignment = .center
        label.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        label.layer.cornerRadius = 12
        label.clipsToBounds = true
        return label
    }()

    private lazy var modeSegment: UISegmentedControl = {
        let segment = UISegmentedControl(items: ["扫描", "问答", "错题"])
        segment.selectedSegmentIndex = 0
        segment.backgroundColor = UIColor.white.withAlphaComponent(0.8)
        segment.addTarget(self, action: #selector(modeChanged), for: .valueChanged)
        return segment
    }()

    private var qaOverlayView: QAOverlayView?

    // MARK: - 生命周期

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupCamera()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        AppState.shared.startScanning()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        AppState.shared.stopScanning()
    }

    // MARK: - UI 设置

    private func setupUI() {
        title = "PAI-CC"
        view.backgroundColor = .black

        view.addSubview(cameraPreviewView)
        view.addSubview(statusLabel)
        view.addSubview(modeSegment)

        cameraPreviewView.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        modeSegment.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            cameraPreviewView.topAnchor.constraint(equalTo: view.topAnchor),
            cameraPreviewView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            cameraPreviewView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            cameraPreviewView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            statusLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.heightAnchor.constraint(equalToConstant: 28),
            statusLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 80),

            modeSegment.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            modeSegment.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            modeSegment.widthAnchor.constraint(equalToConstant: 200)
        ])
    }

    private func setupCamera() {
        cameraPreviewView.addSubview(AppState.shared.cameraService.previewLayer)
        AppState.shared.cameraService.previewLayer.frame = cameraPreviewView.bounds

        // 观察状态变化
        AppState.shared.$scanState.sink { [weak self] state in
            self?.updateStatusLabel(state)
        }.store(in: &cancellables)
    }

    private var cancellables = Set<AnyCancellable>()

    private func updateStatusLabel(_ state: AppState.ScanState) {
        DispatchQueue.main.async {
            switch state {
            case .idle:
                self.statusLabel.text = " 待机 "
                self.statusLabel.backgroundColor = UIColor.gray.withAlphaComponent(0.5)
            case .scanning:
                self.statusLabel.text = " 扫描中 "
                self.statusLabel.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.7)
            case .capturing:
                self.statusLabel.text = " 拍摄中 "
                self.statusLabel.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.7)
            case .analyzing:
                self.statusLabel.text = " 分析中 "
                self.statusLabel.backgroundColor = UIColor.systemOrange.withAlphaComponent(0.7)
            case .qaActive:
                self.statusLabel.text = " 问答中 "
                self.statusLabel.backgroundColor = UIColor.systemPurple.withAlphaComponent(0.7)
            }
        }
    }

    // MARK: - 模式切换

    @objc private func modeChanged() {
        switch modeSegment.selectedSegmentIndex {
        case 0:
            showScanningMode()
        case 1:
            showQAMode()
        case 2:
            showMistakesMode()
        default:
            break
        }
    }

    private func showScanningMode() {
        qaOverlayView?.removeFromSuperview()
        qaOverlayView = nil
    }

    private func showQAMode() {
        if qaOverlayView == nil {
            qaOverlayView = QAOverlayView()
            view.addSubview(qaOverlayView!)
            qaOverlayView?.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                qaOverlayView!.topAnchor.constraint(equalTo: view.topAnchor),
                qaOverlayView!.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                qaOverlayView!.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                qaOverlayView!.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])
        }
    }

    private func showMistakesMode() {
        qaOverlayView?.removeFromSuperview()
        qaOverlayView = nil
        // TODO: 显示错题列表
    }
}

// MARK: - 导入 Combine

import Combine