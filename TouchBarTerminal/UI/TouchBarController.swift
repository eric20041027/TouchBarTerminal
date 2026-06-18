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

    // git 按鈕區（在 repo 內才顯示）
    private let branchLabel = NSTextField(labelWithString: "")
    private lazy var gitStack = makeGitStack()

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

        // 左欄（垂直）
        let leftStack = NSStackView(views: [pathLabel, inputLabel])
        leftStack.orientation = .vertical
        leftStack.spacing = 2
        leftStack.alignment = .leading
        leftStack.distribution = .fillEqually
        leftStack.widthAnchor.constraint(equalToConstant: 240).isActive = true
        leftStack.setContentHuggingPriority(.required, for: .horizontal)

        // 右欄（垂直）：可壓縮，把空間讓給 git 按鈕區
        let rightStack = NSStackView(views: [outputLine1, outputLine2])
        rightStack.orientation = .vertical
        rightStack.spacing = 2
        rightStack.alignment = .leading
        rightStack.distribution = .fillEqually
        rightStack.widthAnchor.constraint(lessThanOrEqualToConstant: 360).isActive = true
        rightStack.setContentHuggingPriority(.defaultLow, for: .horizontal)
        rightStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        // 外層（水平：左欄 | 右輸出 | git 按鈕區）
        let hStack = NSStackView(views: [leftStack, rightStack, gitStack])
        hStack.orientation = .horizontal
        hStack.spacing = 12
        hStack.alignment = .centerY

        // 預設隱藏，進 repo 才顯示（共存模式：與系統 Control Strip 並存）
        gitStack.isHidden = true

        outputItem.view = hStack
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
            gitButton("status", command: "git status -sb"),
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

        // git 按鈕區：在 repo 內才顯示，並更新分支名
        session.$gitBranch
            .receive(on: DispatchQueue.main)
            .sink { [weak self] branch in
                guard let self else { return }
                if let branch {
                    self.branchLabel.stringValue = " \(branch)"
                    self.gitStack.isHidden = false
                } else {
                    self.gitStack.isHidden = true
                }
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
