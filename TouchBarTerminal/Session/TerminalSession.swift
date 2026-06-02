import Foundation
import Combine

@MainActor
final class TerminalSession: ObservableObject {

    @Published var lastOutputLine: String = ""
    @Published var inputBuffer: String = ""
    @Published var promptString: String = "% "
    @Published var isConnected: Bool = false

    private(set) var history = CommandHistory()
    private var ptyBridge = PTYBridge()

    func start() {
        // PTY 輸出 callback
        ptyBridge.onOutput = { [weak self] raw in
            guard let self else { return }
            if let line = AnsiStripper.lastMeaningfulLine(from: raw) {
                self.lastOutputLine = line
                // 偵測 prompt（% 或 $ 結尾）
                if AnsiStripper.isPromptLine(line) {
                    self.promptString = "% "
                }
            }
        }

        ptyBridge.start()
        isConnected = true
    }

    func stop() {
        ptyBridge.stop()
        isConnected = false
    }

    func submitInput() {
        guard !inputBuffer.isEmpty else { return }
        history.push(inputBuffer)
        ptyBridge.writeString(inputBuffer + "\n")
        inputBuffer = ""
    }

    func appendToBuffer(_ char: Character) {
        inputBuffer.append(char)
    }

    func deleteFromBuffer() {
        guard !inputBuffer.isEmpty else { return }
        inputBuffer.removeLast()
    }

    func historyPrevious() {
        if let cmd = history.previous() { inputBuffer = cmd }
    }

    func historyNext() {
        if let cmd = history.next() { inputBuffer = cmd }
    }
}
