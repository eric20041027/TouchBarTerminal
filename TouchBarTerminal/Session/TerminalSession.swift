import Foundation
import Combine

@MainActor
final class TerminalSession: ObservableObject {

    @Published var lastOutputLine: String = ""
    @Published var inputBuffer: String = ""
    @Published var promptString: String = "% "
    @Published var isConnected: Bool = false

    // MARK: - Private

    private let pty = PTYBridge()

    // MARK: - Lifecycle

    func start() {
        pty.onOutput = { [weak self] raw in
            // PTYBridge 在 background thread 呼叫，切回 main thread 更新 UI
            Task { @MainActor [weak self] in
                self?.handle(raw: raw)
            }
        }
        pty.start()
        isConnected = true
    }

    func stop() {
        pty.stop()
        isConnected = false
    }

    // MARK: - Input

    /// 把使用者輸入傳給 zsh
    func send(_ text: String) {
        pty.writeString(text)
    }

    // MARK: - Output processing (private)

    private func handle(raw: String) {
        guard let line = AnsiStripper.lastMeaningfulLine(from: raw) else { return }

        if AnsiStripper.isPromptLine(line) {
            // prompt 行：更新 promptString，清空 inputBuffer
            promptString = line
            inputBuffer = ""
        } else {
            // 一般輸出行：更新 lastOutputLine
            lastOutputLine = line
        }
    }
}
