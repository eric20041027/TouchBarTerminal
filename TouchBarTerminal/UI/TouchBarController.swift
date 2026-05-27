import AppKit
import Combine

/// Touch Bar 視圖控制器（Phase 1 靜態骨架）
@MainActor
final class TouchBarController: NSObject {

    private weak var session: TerminalSession?
    private var cancellables = Set<AnyCancellable>()

    // Touch Bar items
    private let outputItem  = NSCustomTouchBarItem(identifier: .outputLine)
    private let inputItem   = NSCustomTouchBarItem(identifier: .inputLine)

    // Views
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
        bar.defaultItemIdentifiers = [.outputLine]
        return bar
    }

    // MARK: - Setup

    private func setupViews() {
        for label in [outputLabel, inputLabel] {
            label.font = MonoFont.default
            label.textColor = .white
            label.backgroundColor = .clear
            label.isBordered = false
            label.isEditable = false
            label.alignment = .left  // 加這行：文字靠左
        }
        outputLabel.stringValue = "TouchBarTerminal ready"
        inputLabel.stringValue  = "% _"

        let stack = NSStackView(views: [outputLabel, inputLabel])
        stack.orientation = .vertical
        stack.spacing = 2
        stack.distribution = .fillEqually
        stack.alignment = .leading      // 加這行：stack 內容靠左
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
        case .outputLine: return outputItem
        case .inputLine:  return inputItem
        default:          return nil
        }
    }
}

// MARK: - Identifiers
private extension NSTouchBarItem.Identifier {
    static let outputLine = NSTouchBarItem.Identifier("com.tbt.output")
    static let inputLine  = NSTouchBarItem.Identifier("com.tbt.input")
}
