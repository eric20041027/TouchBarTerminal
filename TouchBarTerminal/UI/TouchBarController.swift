import AppKit
import Combine

@MainActor
final class TouchBarController: NSObject {

    private weak var session: TerminalSession?
    private var cancellables = Set<AnyCancellable>()
    private let fontSize: Double

    private let outputItem = NSCustomTouchBarItem(identifier: .terminalOutput)

    // 左側：路徑 + 輸入
    private let pathLabel  = NSTextField(labelWithString: "")
    private let inputLabel = NSTextField(labelWithString: "")

    // 右側：輸出兩行
    private let outputLine1 = NSTextField(labelWithString: "")
    private let outputLine2 = NSTextField(labelWithString: "")

    // git 按鈕區（git 模式時才顯示，與輸出互斥）
    private let branchLabel = NSTextField(labelWithString: "")
    private lazy var gitStack = makeGitStack()
    private lazy var rightStack = makeRightStack()

    // 左上 git 圖示鈕：在 repo 內出現，點擊切換輸出 / git 模式
    private lazy var gitToggleButton = makeGitToggleButton()

    // 右側顯示模式（輸出 / git 按鈕區互斥）
    private var panelMode: GitPanelMode = .output { didSet { applyPanelMode() } }
    // 目前是否在 git repo 內（控制 toggle 鈕是否出現）
    private var isInRepo = false

    init(session: TerminalSession, fontSize: Double = 11) {
        self.session = session
        self.fontSize = fontSize
        super.init()
        setupViews()
        bindSession()
    }

    func makeTouchBar() -> NSTouchBar {
        let bar = NSTouchBar()
        bar.delegate = self
        bar.defaultItemIdentifiers = [.terminalOutput]
        return bar
    }

    // MARK: - Setup

    private func setupViews() {
        // 共用樣式
        for label in [pathLabel, inputLabel, outputLine1, outputLine2] {
            label.font = NSFont(name: "SFMono-Regular", size: fontSize)
                      ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
            label.textColor = .white
            label.backgroundColor = .clear
            label.isBordered = false
            label.isEditable = false
            label.alignment = .left
            label.lineBreakMode = .byTruncatingTail   // 太長就尾端省略
        }

        // 右側輸出用稍微暗一點的顏色區隔
        outputLine1.textColor = .systemGreen
        outputLine2.textColor = .systemGreen

        // 左欄（垂直）：路徑 + 輸入，固定寬度，永遠顯示
        let leftStack = NSStackView(views: [pathLabel, inputLabel])
        leftStack.orientation = .vertical
        leftStack.spacing = 2
        leftStack.alignment = .leading
        leftStack.distribution = .fillEqually
        leftStack.widthAnchor.constraint(equalToConstant: 240).isActive = true
        leftStack.setContentHuggingPriority(.required, for: .horizontal)

        // 外層（水平：左欄 | git 圖示鈕 | 右側區）。
        // 右側區的輸出與 git 按鈕互斥（applyPanelMode 控制），所以不會互相擠壓。
        let hStack = NSStackView(views: [leftStack, gitToggleButton, rightStack, gitStack])
        hStack.orientation = .horizontal
        hStack.spacing = 10
        hStack.alignment = .centerY

        // 初始狀態：非 repo → 不顯示 toggle，顯示輸出
        outputItem.view = hStack
        applyPanelMode()
    }

    /// 右欄（垂直）：終端輸出兩行。
    private func makeRightStack() -> NSStackView {
        let stack = NSStackView(views: [outputLine1, outputLine2])
        stack.orientation = .vertical
        stack.spacing = 2
        stack.alignment = .leading
        stack.distribution = .fillEqually
        stack.widthAnchor.constraint(lessThanOrEqualToConstant: 400).isActive = true
        return stack
    }

    /// 左上 git 圖示鈕：點擊切換輸出 / git 模式。
    private func makeGitToggleButton() -> NSButton {
        let image = NSImage(systemSymbolName: "arrow.triangle.branch",
                            accessibilityDescription: "Git") ?? NSImage()
        let button = NSButton(image: image, target: self, action: #selector(gitToggleTapped))
        button.bezelStyle = .rounded
        button.imagePosition = .imageOnly
        button.setContentHuggingPriority(.required, for: .horizontal)
        return button
    }

    @objc private func gitToggleTapped() {
        panelMode = panelMode.toggled()
    }

    /// 套用目前模式到 UI：輸出與 git 按鈕區互斥顯示。
    private func applyPanelMode() {
        gitToggleButton.isHidden = !isInRepo
        // git 模式（且在 repo）→ 顯示 git 按鈕區；否則顯示輸出
        let showGit = (panelMode == .git && isInRepo)
        gitStack.isHidden = !showGit
        rightStack.isHidden = showGit
    }

    /// 建立 git 按鈕區：分支名 + status / add / commit / push。
    private func makeGitStack() -> NSStackView {
        branchLabel.font = NSFont(name: "SFMono-Regular", size: fontSize)
                        ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        branchLabel.textColor = .systemOrange
        branchLabel.backgroundColor = .clear
        branchLabel.isBordered = false
        branchLabel.isEditable = false
        branchLabel.lineBreakMode = .byTruncatingTail
        branchLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let buttons = [
            gitButton("status", command: "git status"),
            gitButton("add",    command: "git add -A"),
            gitButton("commit", command: "git commit"),
            gitButton("push",   command: "git push"),
        ]

        let stack = NSStackView(views: [branchLabel] + buttons)
        stack.orientation = .horizontal
        stack.spacing = 4
        stack.alignment = .centerY
        stack.setContentHuggingPriority(.required, for: .horizontal)
        stack.setContentCompressionResistancePriority(.required, for: .horizontal)
        return stack
    }

    private func gitButton(_ title: String, command: String) -> NSButton {
        let button = NSButton(title: title, target: self, action: #selector(gitButtonTapped(_:)))
        button.bezelStyle = .rounded
        button.identifier = NSUserInterfaceItemIdentifier(command)   // 把指令藏在 identifier
        return button
    }

    @objc private func gitButtonTapped(_ sender: NSButton) {
        guard let command = sender.identifier?.rawValue else { return }
        session?.runCommand(command)
        // 跑完指令自動切回輸出，方便立刻看到結果
        panelMode = .output
    }

    private func bindSession() {
        guard let session else { return }

        // 左側路徑
        session.$currentPath
            .receive(on: DispatchQueue.main)
            .sink { [weak self] path in
                self?.pathLabel.stringValue = path
            }
            .store(in: &cancellables)

        // 左側輸入行（即時模式：直接顯示 zsh echo 回來的目前行）
        session.$currentLine
            .receive(on: DispatchQueue.main)
            .sink { [weak self] line in
                self?.inputLabel.stringValue = line
            }
            .store(in: &cancellables)

        // 右側輸出兩行
        session.$outputLines
            .receive(on: DispatchQueue.main)
            .sink { [weak self] lines in
                self?.outputLine1.stringValue = lines.count > 0 ? lines[0] : ""
                self?.outputLine2.stringValue = lines.count > 1 ? lines[1] : ""
            }
            .store(in: &cancellables)

        // git 狀態：更新分支名 + repo 內外切換（離開 repo 強制回輸出模式）
        session.$gitBranch
            .receive(on: DispatchQueue.main)
            .sink { [weak self] branch in
                guard let self else { return }
                self.isInRepo = (branch != nil)
                if let branch {
                    self.branchLabel.stringValue = " \(branch)"
                }
                // 離開 repo 時把模式拉回 output（state machine 決定）
                self.panelMode = self.panelMode.afterRepoChange(isRepo: self.isInRepo)
                // 仍在 repo 但模式沒變時 didSet 不會觸發，這裡補一次套用
                self.applyPanelMode()
            }
            .store(in: &cancellables)
    }
}

// MARK: - NSTouchBarDelegate
extension TouchBarController: NSTouchBarDelegate {
    func touchBar(_ touchBar: NSTouchBar,
                  makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        switch identifier {
        case .terminalOutput: return outputItem
        default: return nil
        }
    }
}

// MARK: - Identifier
private extension NSTouchBarItem.Identifier {
    static let terminalOutput = NSTouchBarItem.Identifier("com.tbt.output")
}
