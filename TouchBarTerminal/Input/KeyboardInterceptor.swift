import AppKit

/// 即時模式：把按鍵原封不動轉發給 zsh，由 zsh 處理 echo/補全/歷史。
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

        // Control 組合鍵：送對應的控制字元（⌃C=0x03, ⌃D=0x04, ⌃L=0x0C ...）
        if flags.contains(.control),
           let chars = event.charactersIgnoringModifiers,
           let scalar = chars.unicodeScalars.first,
           scalar.value >= 0x61 && scalar.value <= 0x7a {        // a–z
            let ctrlByte = UInt8(scalar.value - 0x60)            // a→1, c→3, l→12
            session.sendBytes([ctrlByte])
            return nil
        }

        switch event.keyCode {
        case 36:  // Enter → 送 \r（zsh 認回車）
            session.sendBytes([0x0d])
            return nil
        case 51:  // Backspace → 送 DEL (0x7f)
            session.sendBytes([0x7f])
            return nil
        case 48:  // Tab → 送 \t，zsh 自己補全
            session.sendBytes([0x09])
            return nil
        case 126: // ↑ → ESC [ A
            session.sendBytes([0x1b, 0x5b, 0x41])
            return nil
        case 125: // ↓ → ESC [ B
            session.sendBytes([0x1b, 0x5b, 0x42])
            return nil
        case 124: // → ESC [ C
            session.sendBytes([0x1b, 0x5b, 0x43])
            return nil
        case 123: // ← ESC [ D
            session.sendBytes([0x1b, 0x5b, 0x44])
            return nil
        default:
            break
        }

        // 一般可列印字元：即時送進 zsh（排除 Cmd 組合鍵）
        if let chars = event.characters,
           !flags.contains(.command),
           !flags.contains(.control) {
            for char in chars {
                session.sendCharacter(char)
            }
            return nil
        }

        return event
    }
}
