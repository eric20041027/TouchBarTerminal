import AppKit
import Combine

/// Menu bar 狀態列圖示
final class StatusItemController {

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private var cancellables = Set<AnyCancellable>()

    init(session: TerminalSession) {
        setupMenu()
        bind(session: session)
    }

    private func setupMenu() {
        statusItem.button?.title = "⌨"
        statusItem.button?.toolTip = "TouchBarTerminal — ⌃⌥Space to toggle"

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "TouchBarTerminal", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))
        statusItem.menu = menu
    }

    private func bind(session: TerminalSession) {
        session.$isConnected
            .receive(on: DispatchQueue.main)
            .sink { [weak self] connected in
                self?.statusItem.button?.title = connected ? "⌨" : "⌨?"
            }
            .store(in: &cancellables)
    }
}
