import AppKit

final class KeyboardInterceptor {

    private weak var session: TerminalSession?
    private var monitor: Any?

    init(session: TerminalSession) {
        self.session = session
    }

    func start() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let session = self.session else { return event }
            return self.handle(event: event, session: session)
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    // MARK: - Private

    @MainActor
    private func handle(event: NSEvent, session: TerminalSession) -> NSEvent? {
        let flags = event.modifierFlags

        // ⌃C → 中斷
        if flags.contains(.control),
           event.charactersIgnoringModifiers == "c" {
            session.sendControlChar(0x03)
            return nil
        }

        // ⌃L → 清除輸出
        if flags.contains(.control),
           event.charactersIgnoringModifiers == "l" {
            session.lastOutputLine = ""
            return nil
        }

        switch event.keyCode {
        case 36:  // Enter
            session.submitInput()
            return nil
        case 51:  // Backspace
            session.deleteFromBuffer()
            return nil
        case 126: // ↑
            session.historyPrevious()
            return nil
        case 125: // ↓
            session.historyNext()
            return nil
        case 48:  // Tab
            session.sendControlChar(0x09)
            return nil
        default:
            break
        }

        // 一般可列印字元（排除 Cmd、Ctrl 組合鍵）
        if let chars = event.characters,
           !flags.contains(.command),
           !flags.contains(.control) {
            for char in chars {
                session.appendToBuffer(char)
            }
            return nil
        }

        return event  // 不處理的事件原封不動傳回
    }
}
