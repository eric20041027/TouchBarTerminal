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
        statusItem.button?.action = #selector(statusButtonClicked(_:))
        statusItem.button?.target = self
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func statusButtonClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent!
        if event.type == .rightMouseUp {
            // 右鍵：顯示選單
            let menu = NSMenu()
            menu.addItem(NSMenuItem(title: "TouchBarTerminal", action: nil, keyEquivalent: ""))
            menu.addItem(.separator())
            menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            // 左鍵：activate App，Touch Bar 恢復
            NSApp.activate(ignoringOtherApps: true)
        }
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
