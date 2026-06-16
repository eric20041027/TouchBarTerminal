import Foundation
import Combine

@MainActor
final class TerminalSession: ObservableObject {

    @Published var lastOutputLine: String = ""
    @Published var inputBuffer: String = ""
    @Published var promptString: String = "% "
    @Published var isConnected: Bool = false
    @Published var currentPath: String = "~"      // 左側顯示的路徑（從 prompt 解析）
    @Published var outputLines: [String] = []      // 右側顯示的輸出（最多兩行）

    private(set) var history = CommandHistory()
    private var ptyBridge = PTYBridge()
    private var lastCommand: String = ""   // 剛送出的指令，用來過濾 echo

    func start() {
        // PTY 輸出 callback
        ptyBridge.onOutput = { [weak self] raw in
            guard let self else { return }

            let lines = AnsiStripper.strip(raw)
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }

            for line in lines {
                if AnsiStripper.isPromptLine(line) {
                    // prompt 行：解析路徑放到左側，不蓋掉右側輸出
                    if let path = AnsiStripper.extractPath(from: line) {
                        self.currentPath = path
                    }
                } else if line == self.lastCommand {
                    // 過濾掉 zsh echo 回來的指令本身
                    continue
                } else {
                    // 一般輸出行：累積到右側，最多兩行
                    self.outputLines.append(line)
                    if self.outputLines.count > 2 {
                        self.outputLines.removeFirst()
                    }
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
        lastCommand = inputBuffer   // 記住指令，過濾它的 echo
        outputLines = []            // 送出新指令時清空右側舊輸出
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
    func sendControlChar(_ byte: UInt8) {
        let data = Data([byte])
        ptyBridge.writeData(data)
    }
}
