import AppKit
import Combine

@MainActor
final class StatusItemController {

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private var cancellables = Set<AnyCancellable>()

    init(session: TerminalSession) {
        setupMenu()
        bindSession(session)
    }

    private func setupMenu() {
        statusItem.button?.title = "⌨"

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "TouchBarTerminal", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    private func bindSession(_ session: TerminalSession) {
        session.$isConnected
            .receive(on: DispatchQueue.main)
            .sink { [weak self] connected in
                self?.statusItem.button?.title = connected ? "⌨" : "⌨?"
            }
            .store(in: &cancellables)
    }
}
