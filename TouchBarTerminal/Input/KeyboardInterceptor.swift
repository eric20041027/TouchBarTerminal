import AppKit

/// 把按鍵翻譯成 TerminalSession 的 buffer 操作（混合模式）。
/// 正常輸入走 buffer，Tab/密碼由 session 內部決定是否即時轉發。
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

        // Control 組合鍵：送對應控制字元（⌃C=0x03 等）
        if flags.contains(.control),
           let chars = event.charactersIgnoringModifiers,
           let scalar = chars.unicodeScalars.first,
           scalar.value >= 0x61 && scalar.value <= 0x7a {        // a–z
            session.sendControl(UInt8(scalar.value - 0x60))
            return nil
        }

        switch event.keyCode {
        case 36:  session.submit();            return nil   // Enter
        case 51:  session.backspace();         return nil   // Backspace
        case 48:  session.requestCompletion(); return nil   // Tab
        case 126: session.historyUp();         return nil   // ↑
        case 125: session.historyDown();       return nil   // ↓
        case 123: session.moveCursorLeft();    return nil   // ←
        case 124: session.moveCursorRight();   return nil   // →
        default:  break
        }

        // 一般可列印字元
        if let chars = event.characters,
           !flags.contains(.command),
           !flags.contains(.control) {
            for char in chars { session.typeCharacter(char) }
            return nil
        }

        return event
    }
}
