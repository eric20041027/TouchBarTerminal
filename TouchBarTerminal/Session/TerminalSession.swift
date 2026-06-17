import Foundation
import Combine

/// 混合模式 ViewModel。
///
/// 正常輸入用「自己的 inputBuffer」（完全可控，游標/箭頭/歷史不會亂）；
/// 只有按 Tab 補全與 sudo 密碼輸入時，才把字元即時轉發給 zsh。
///
/// - 打字 / Backspace / ←→ 游標 / ↑↓ 歷史 → 操作 inputBuffer，不依賴 zsh echo
/// - Enter → 送 buffer + \n 給 zsh，推進歷史
/// - Tab → 本地路徑補全（PathCompleter），不送 zsh
/// - 密碼模式 → 即時轉發，自己數位數顯示 🔒 •••••
///
/// zsh 的「輸出」由 [TerminalParser] 解析後顯示在右側。
@MainActor
final class TerminalSession: ObservableObject {

    /// 左側下排：prompt + 目前輸入（含游標）
    @Published var currentLine: String = "% _"
    /// 左側上排：目前路徑
    @Published var currentPath: String = "~"
    /// 右側：最近的輸出
    @Published var outputLines: [String] = []
    /// menu bar 連線狀態
    @Published var isConnected: Bool = false

    private var ptyBridge = PTYBridge()
    private var parser = TerminalParser()
    private let config: AppConfig
    private var history = CommandHistory()

    // 自己的輸入緩衝與游標位置
    private var inputBuffer = ""
    private var cursorPos = 0          // 游標在 inputBuffer 中的索引（0…count）

    // 模式旗標
    private var inPasswordMode = false
    private var passwordDigits = 0

    // 游標閃爍
    private var cursorTimer: Timer?
    private var cursorVisible = true

    init(config: AppConfig = .load()) {
        self.config = config
    }

    // MARK: - Lifecycle

    func start() {
        ptyBridge.onOutput = { [weak self] raw in
            guard let self else { return }
            self.handleOutput(raw)
        }
        ptyBridge.start(shell: config.shell)
        isConnected = true
        startCursorBlink()
        renderInputLine()
    }

    func stop() {
        cursorTimer?.invalidate()
        cursorTimer = nil
        ptyBridge.stop()
        isConnected = false
    }

    // MARK: - 輸入處理（buffer 模式）

    func typeCharacter(_ char: Character) {
        if inPasswordMode {
            ptyBridge.writeString(String(char))
            passwordDigits += 1
            currentLine = "🔒 " + String(repeating: "•", count: passwordDigits)
            return
        }
        inputBuffer.insert(char, at: bufferIndex(cursorPos))
        cursorPos += 1
        renderInputLine()
    }

    func backspace() {
        if inPasswordMode {
            ptyBridge.writeData(Data([0x7f]))
            passwordDigits = max(0, passwordDigits - 1)
            currentLine = "🔒 " + String(repeating: "•", count: passwordDigits)
            return
        }
        guard cursorPos > 0 else { return }
        inputBuffer.remove(at: bufferIndex(cursorPos - 1))
        cursorPos -= 1
        renderInputLine()
    }

    func moveCursorLeft() {
        guard !inPasswordMode, cursorPos > 0 else { return }
        cursorPos -= 1
        renderInputLine()
    }

    func moveCursorRight() {
        guard !inPasswordMode, cursorPos < inputBuffer.count else { return }
        cursorPos += 1
        renderInputLine()
    }

    func historyUp() {
        guard !inPasswordMode, let cmd = history.previous() else { return }
        inputBuffer = cmd
        cursorPos = cmd.count
        renderInputLine()
    }

    func historyDown() {
        guard !inPasswordMode else { return }
        inputBuffer = history.next() ?? ""
        cursorPos = inputBuffer.count
        renderInputLine()
    }

    func submit() {
        if inPasswordMode {
            ptyBridge.writeData(Data([0x0d]))
            passwordDigits = 0
            currentLine = "🔒 ..."
            return
        }
        let cmd = inputBuffer
        if !cmd.trimmingCharacters(in: .whitespaces).isEmpty {
            history.push(cmd)
        }
        // 先 ⌃U 清掉 zsh 行內可能的殘留（如 Tab 補全後的內容），再送完整指令
        ptyBridge.writeData(Data([0x15]))
        ptyBridge.writeString(cmd + "\n")
        inputBuffer = ""
        cursorPos = 0
        renderInputLine()
    }

    /// Tab：本地路徑補全（不送 zsh，避免雙向同步累加問題）。
    /// 唯一結果 → 補進 buffer；多個 → 候選顯示在右側。
    func requestCompletion() {
        guard !inPasswordMode else { return }
        // 優先用 zsh 子行程的真實 cwd（可靠）；查不到才回退用 prompt 顯示路徑
        let cwd = ptyBridge.currentDirectory
            ?? (currentPath as NSString).expandingTildeInPath
        switch PathCompleter.complete(inputBuffer, cwd: cwd) {
        case .unique(let completed):
            inputBuffer = completed
            cursorPos = completed.count
            renderInputLine()
        case .candidates(let list):
            outputLines = Array(list.prefix(config.outputLines))
        case .none:
            break
        }
    }

    func sendControl(_ byte: UInt8) {
        ptyBridge.writeData(Data([byte]))
        if byte == 0x03 {   // ⌃C：清空輸入
            inputBuffer = ""
            cursorPos = 0
            renderInputLine()
        }
    }

    // MARK: - 輸出處理

    private func handleOutput(_ raw: String) {
        for event in parser.feed(raw) {
            apply(event)
        }
    }

    private func apply(_ event: ParserEvent) {
        switch event {
        case .prompt(let path):
            currentPath = path
        case .output(let line):
            outputLines.append(line)
            while outputLines.count > config.outputLines { outputLines.removeFirst() }
        case .currentInput:
            // buffer 模式：輸入完全由我們掌控，忽略 zsh 的即時 echo
            break
        case .passwordPrompt(let prompt):
            inPasswordMode = true
            passwordDigits = 0
            outputLines.append(prompt)
            while outputLines.count > config.outputLines { outputLines.removeFirst() }
            currentLine = "🔒 "
        case .passwordEnded:
            inPasswordMode = false
            passwordDigits = 0
            renderInputLine()
        }
    }

    // MARK: - 顯示

    private func startCursorBlink() {
        guard config.cursorBlink else { return }
        cursorTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.toggleCursor() }
        }
    }

    private func toggleCursor() {
        guard !inPasswordMode else { return }
        cursorVisible.toggle()
        renderInputLine()
    }

    /// 用 inputBuffer + 游標位置重組顯示行
    private func renderInputLine() {
        guard !inPasswordMode else { return }
        cursorVisible = true
        let cursorChar = "|"
        var shown = inputBuffer
        shown.insert(contentsOf: cursorChar, at: bufferIndex(cursorPos))
        currentLine = "% " + shown
    }

    private func bufferIndex(_ offset: Int) -> String.Index {
        inputBuffer.index(inputBuffer.startIndex, offsetBy: offset)
    }
}
