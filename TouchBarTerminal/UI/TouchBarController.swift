import AppKit
import Combine
import UserNotifications

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

    // 番茄鐘（最左側常駐）：▶/⏸ 鈕 + 剩餘時間 + 進度光帶
    private let pomodoroLabel = NSTextField(labelWithString: "")
    private let pomodoroBar = NSProgressIndicator()
    private lazy var pomodoroButton = makePomodoroButton()
    private lazy var pomodoroStack = makePomodoroStack()

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
        leftStack.widthAnchor.constraint(equalToConstant: 200).isActive = true
        leftStack.setContentHuggingPriority(.required, for: .horizontal)

        // 外層（水平：番茄鐘 | 左欄 | git 圖示鈕 | 右側區）。
        // 番茄鐘最左側常駐（會動、永遠可見）；右側區的輸出與 git 按鈕互斥。
        let hStack = NSStackView(views: [pomodoroStack, leftStack, gitToggleButton, rightStack, gitStack])
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

    // MARK: - 番茄鐘 UI

    /// ▶/⏸ 按鈕。
    private func makePomodoroButton() -> NSButton {
        let image = NSImage(systemSymbolName: "play.fill", accessibilityDescription: "Start")
            ?? NSImage()
        let button = NSButton(image: image, target: self, action: #selector(pomodoroTapped))
        button.bezelStyle = .rounded
        button.imagePosition = .imageOnly
        button.setContentHuggingPriority(.required, for: .horizontal)
        return button
    }

    @objc private func pomodoroTapped() {
        session?.togglePomodoro()
    }

    /// 到點：Touch Bar 紅字 + 閃爍幾下，並發系統通知（有聲音，專注時沒看也聽得到）。
    private func handlePomodoroFinished() {
        updatePomodoroUI(text: "00:00", progress: 1, running: false, finished: true)
        flashPomodoro(times: 6)

        let content = UNMutableNotificationContent()
        content.title = "🍅 番茄鐘結束"
        content.body = "25 分鐘到了，休息一下。"
        content.sound = .default
        let request = UNNotificationRequest(identifier: "pomodoro.finished",
                                            content: content, trigger: nil)
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            center.add(request)
        }
    }

    /// Touch Bar 番茄鐘標籤閃爍（紅 ↔ 透明）。
    private func flashPomodoro(times: Int) {
        guard times > 0 else {
            pomodoroLabel.textColor = .secondaryLabelColor   // 閃完回 idle 灰
            return
        }
        pomodoroLabel.textColor = (times % 2 == 0) ? .systemRed : .clear
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.flashPomodoro(times: times - 1)
        }
    }

    /// 番茄鐘區：▶/⏸ 鈕 + 剩餘時間 + 進度光帶（垂直疊時間與光帶）。
    private func makePomodoroStack() -> NSStackView {
        pomodoroLabel.font = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .medium)
        pomodoroLabel.textColor = .systemRed
        pomodoroLabel.backgroundColor = .clear
        pomodoroLabel.isBordered = false
        pomodoroLabel.isEditable = false
        pomodoroLabel.alignment = .center

        pomodoroBar.isIndeterminate = false
        pomodoroBar.minValue = 0
        pomodoroBar.maxValue = 1
        pomodoroBar.doubleValue = 0
        pomodoroBar.controlSize = .small
        pomodoroBar.widthAnchor.constraint(equalToConstant: 56).isActive = true

        let textAndBar = NSStackView(views: [pomodoroLabel, pomodoroBar])
        textAndBar.orientation = .vertical
        textAndBar.spacing = 2
        textAndBar.alignment = .centerX

        let stack = NSStackView(views: [pomodoroButton, textAndBar])
        stack.orientation = .horizontal
        stack.spacing = 4
        stack.alignment = .centerY
        stack.setContentHuggingPriority(.required, for: .horizontal)
        stack.setContentCompressionResistancePriority(.required, for: .horizontal)
        return stack
    }

    /// 更新番茄鐘顯示（時間、進度、▶/⏸ 圖示、到點變色）。
    private func updatePomodoroUI(text: String, progress: Double, running: Bool, finished: Bool) {
        pomodoroLabel.stringValue = text
        pomodoroBar.doubleValue = progress
        let symbol = running ? "pause.fill" : "play.fill"
        pomodoroButton.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        // 剩最後一分鐘或到點 → 紅；倒數中 → 橙；idle → 灰
        if finished || (running && progress > 0 && (1 - progress) * Double(25 * 60) <= 60) {
            pomodoroLabel.textColor = .systemRed
        } else if running {
            pomodoroLabel.textColor = .systemOrange
        } else {
            pomodoroLabel.textColor = .secondaryLabelColor
        }
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
            gitButton("commit", command: Self.commitSentinel),  // 特例：進 commit 訊息模式
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

    /// commit 按鈕的特例識別字：不是直接跑指令，而是進 commit 訊息輸入模式。
    private static let commitSentinel = "__enter_commit_mode__"

    @objc private func gitButtonTapped(_ sender: NSButton) {
        guard let command = sender.identifier?.rawValue else { return }
        if command == Self.commitSentinel {
            // 進 commit 訊息模式：切回輸出（左側顯示訊息輸入框），由 onCommitModeChanged 處理收尾
            panelMode = .output
            session?.enterCommitMode()
            return
        }
        session?.runCommand(command)
        // 跑完指令自動切回輸出，方便立刻看到結果
        panelMode = .output
    }

    private func bindSession() {
        guard let session else { return }

        // commit 訊息模式進/出：都維持輸出模式（左側顯示訊息框 / 結果）
        session.onCommitModeChanged = { [weak self] _ in
            self?.panelMode = .output
        }

        // 番茄鐘顯示：時間 / 進度 / running 三者一起更新 UI
        Publishers.CombineLatest3(
            session.$pomodoroText, session.$pomodoroProgress, session.$pomodoroRunning
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] text, progress, running in
            self?.updatePomodoroUI(text: text, progress: progress, running: running, finished: false)
        }
        .store(in: &cancellables)

        // 番茄鐘到點：閃爍 + 系統通知
        session.onPomodoroFinished = { [weak self] in
            self?.handlePomodoroFinished()
        }

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
