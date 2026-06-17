import Foundation
import Combine

/// 即時模式（passthrough）的 ViewModel。
///
/// 重構後職責單一：
/// - 管理 @Published 顯示狀態
/// - 把使用者輸入即時轉發給 PTY
/// - 把 PTY 輸出交給 TerminalParser，再把產出的事件套到狀態
///
/// 所有「解析 zsh 輸出」的複雜邏輯都在 [TerminalParser]，這裡保持薄。
@MainActor
final class TerminalSession: ObservableObject {

    /// 左側下排：目前正在輸入的指令（prompt 符號後的部分）
    @Published var currentLine: String = "% _"
    /// 左側上排：目前路徑
    @Published var currentPath: String = "~"
    /// 右側：最近的輸出（最多兩行）
    @Published var outputLines: [String] = []
    /// menu bar 連線狀態
    @Published var isConnected: Bool = false

    private var ptyBridge = PTYBridge()
    private var parser = TerminalParser()

    /// 密碼模式：zsh 不 echo，由我們自己數使用者打了幾個字
    private var inPasswordMode = false
    private var passwordDigits = 0

    // MARK: - Lifecycle

    func start() {
        ptyBridge.onOutput = { [weak self] raw in
            guard let self else { return }
            for event in self.parser.feed(raw) {
                self.apply(event)
            }
        }
        ptyBridge.start()
        isConnected = true
    }

    func stop() {
        ptyBridge.stop()
        isConnected = false
    }

    // MARK: - 輸入（即時轉發給 zsh）

    func sendCharacter(_ char: Character) {
        ptyBridge.writeString(String(char))
        // 密碼模式下自己數位數（zsh 不會 echo）
        if inPasswordMode {
            passwordDigits += 1
            currentLine = "🔒 " + String(repeating: "•", count: passwordDigits)
        }
    }

    func sendBytes(_ bytes: [UInt8]) {
        ptyBridge.writeData(Data(bytes))
        guard inPasswordMode else { return }
        // 密碼模式下調整位數顯示
        if bytes == [0x7f] {                 // Backspace
            passwordDigits = max(0, passwordDigits - 1)
            currentLine = "🔒 " + String(repeating: "•", count: passwordDigits)
        } else if bytes == [0x0d] {          // Enter → 密碼送出，等結果
            passwordDigits = 0
            currentLine = "🔒 ..."
        }
    }

    // MARK: - 套用解析事件

    private func apply(_ event: ParserEvent) {
        switch event {
        case .prompt(let path):
            currentPath = path
        case .output(let line):
            outputLines.append(line)
            if outputLines.count > 2 { outputLines.removeFirst() }
        case .currentInput(let text):
            currentLine = "% " + text + "_"
        case .passwordPrompt(let prompt):
            inPasswordMode = true
            passwordDigits = 0
            outputLines.append(prompt)
            if outputLines.count > 2 { outputLines.removeFirst() }
            currentLine = "🔒 "
        case .passwordEnded:
            inPasswordMode = false
            passwordDigits = 0
        }
    }
}
