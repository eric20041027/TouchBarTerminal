import AppKit
import Combine

@MainActor
final class TouchBarController: NSObject {

    private weak var session: TerminalSession?
    private var cancellables = Set<AnyCancellable>()

    // Touch Bar item（一個格子裝兩行文字）
    private let outputItem = NSCustomTouchBarItem(identifier: .terminalOutput)

    // 兩行文字
    private let outputLabel = NSTextField(labelWithString: "")
    private let inputLabel  = NSTextField(labelWithString: "")

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

    // MARK: - Private

    private func setupViews() {
        // 設定兩個 label 的樣式
        for label in [outputLabel, inputLabel] {
            label.font = NSFont(name: "SFMono-Regular", size: 11)
                      ?? NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
            label.textColor = .white
            label.backgroundColor = .clear
            label.isBordered = false
            label.isEditable = false
            label.alignment = .left
        }
        outputLabel.stringValue = "TouchBarTerminal ready"
        inputLabel.stringValue  = "% _"

        // 垂直 stack
        let stack = NSStackView(views: [outputLabel, inputLabel])
        stack.orientation  = .vertical
        stack.spacing      = 2
        stack.distribution = .fillEqually
        stack.alignment    = .leading
        stack.widthAnchor.constraint(equalToConstant: 600).isActive = true

        outputItem.view = stack
    }

    private func bindSession() {
        guard let session else { return }

        session.$lastOutputLine
            .receive(on: DispatchQueue.main)
            .sink { [weak self] line in
                self?.outputLabel.stringValue = line.isEmpty ? " " : line
            }
            .store(in: &cancellables)

        session.$inputBuffer
            .combineLatest(session.$promptString)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] buffer, prompt in
                self?.inputLabel.stringValue = "\(prompt)\(buffer)_"
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
