import Foundation
import Combine

/// ViewModel：持有 PTY 狀態，驅動 Touch Bar 更新
@MainActor
final class TerminalSession: ObservableObject {

    @Published var lastOutputLine: String = ""
    @Published var inputBuffer: String = ""
    @Published var promptString: String = "% "
    @Published var isConnected: Bool = false

    private(set) var history = CommandHistory()
    // TODO Phase 2: private var ptyBridge: PTYBridge?

    func start() {
        // TODO Phase 2: fork PTY
        isConnected = true
    }

    func stop() {
        // TODO Phase 2: teardown PTY
        isConnected = false
    }

    func submitInput() {
        guard !inputBuffer.isEmpty else { return }
        history.push(inputBuffer)
        // TODO Phase 3: ptyBridge?.writeString(inputBuffer + "\n")
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
