import AppKit
import Combine

@MainActor
final class TouchBarController: NSObject {

    private weak var session: TerminalSession?
    private var cancellables = Set<AnyCancellable>()

    private let outputItem = NSCustomTouchBarItem(identifier: .terminalOutput)

    // 左側：路徑 + 輸入
    private let pathLabel  = NSTextField(labelWithString: "")
    private let inputLabel = NSTextField(labelWithString: "")

    // 右側：輸出兩行
    private let outputLine1 = NSTextField(labelWithString: "")
    private let outputLine2 = NSTextField(labelWithString: "")

    init(session: TerminalSession) {
        self.session = session
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
            label.font = NSFont(name: "SFMono-Regular", size: 11)
                      ?? NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
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
        leftStack.widthAnchor.constraint(equalToConstant: 280).isActive = true

        // 右欄（垂直）
        let rightStack = NSStackView(views: [outputLine1, outputLine2])
        rightStack.orientation = .vertical
        rightStack.spacing = 2
        rightStack.alignment = .leading
        rightStack.distribution = .fillEqually
        rightStack.widthAnchor.constraint(equalToConstant: 360).isActive = true

        // 外層（水平，左右並排）
        let hStack = NSStackView(views: [leftStack, rightStack])
        hStack.orientation = .horizontal
        hStack.spacing = 12
        hStack.alignment = .centerY

        outputItem.view = hStack
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

        // 左側輸入行
        session.$inputBuffer
            .combineLatest(session.$promptString)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] buffer, prompt in
                self?.inputLabel.stringValue = "\(prompt)\(buffer)_"
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
