import Foundation

/// 解析器產出的結構化事件。
/// TerminalSession 只需把這些事件套到 @Published 狀態，不必碰解析細節。
enum ParserEvent: Equatable {
    /// 偵測到 prompt 行，帶出解析到的路徑
    case prompt(path: String)
    /// 一行完整的指令輸出
    case output(line: String)
    /// 目前正在輸入的行（即時更新），text 是 prompt 符號後的使用者輸入
    case currentInput(text: String)
}

/// 純邏輯的終端輸出解析器。
///
/// 職責單一：吃 zsh 送來的 raw 字串，吐出結構化 `ParserEvent`。
/// 不依賴 UI、不依賴 PTY、不持有顯示狀態 —— 因此 100% 可單元測試。
///
/// 處理的細節：
/// - ANSI escape 剝除
/// - `\r`（游標回行首，prompt 重繪）與 `\n`（換行）
/// - prompt 行偵測（含 `user@host` 或結尾 `% / $ / #`）
/// - 指令 echo 過濾（prompt 行只解析路徑，不當輸出）
/// - prompt 與使用者輸入黏在同一行時切開
struct TerminalParser {

    /// 累積目前這一行（已剝除 ANSI）
    private var lineBuffer = ""

    /// 餵入一段 raw 資料，回傳這段觸發的所有事件（依序）。
    mutating func feed(_ raw: String) -> [ParserEvent] {
        var events: [ParserEvent] = []
        // 先把 \r\n 與 \r 正規化成 \n。
        // 注意：Swift 會把 "\r\n" 視為單一 Character（grapheme cluster），
        // 逐字元 switch 無法匹配單獨的 \n/\r，所以必須先正規化成統一的 \n。
        let normalized = AnsiStripper.strip(raw)
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        for char in normalized {
            switch char {
            case "\n":
                // 換行或回行首：目前行結束
                events.append(contentsOf: flush())
            case "\u{7f}", "\u{08}":
                // Backspace / Delete echo
                if !lineBuffer.isEmpty { lineBuffer.removeLast() }
            default:
                lineBuffer.append(char)
            }
        }

        // 行還沒結束 → 即時回報目前輸入內容
        events.append(currentInputEvent(from: lineBuffer))
        return events
    }

    // MARK: - Private

    /// 一行結束時分類：prompt 回顯 → 解析路徑；其餘 → 輸出
    private mutating func flush() -> [ParserEvent] {
        let line = lineBuffer.trimmingCharacters(in: .whitespaces)
        lineBuffer = ""

        guard !line.isEmpty else { return [] }

        // prompt + 黏住的指令/輸出：先看有沒有 prompt 標記
        if let promptRange = Self.promptSymbolRange(in: line) {
            var events: [ParserEvent] = []
            if let path = Self.extractPath(fromPromptPrefix: String(line[..<promptRange.upperBound])) {
                events.append(.prompt(path: path))
            }
            // prompt 符號後若黏了輸出（如 "%pwd" 後接 "/Users/x"），這裡只解析路徑，
            // 黏住的指令名是 echo，不當輸出。獨立的輸出行會在後續 \n 各自 flush。
            return events
        }

        if isPromptLine(line) {
            if let path = Self.extractPath(fromPromptPrefix: line) {
                return [.prompt(path: path)]
            }
            return []
        }

        return [.output(line: line)]
    }

    /// 目前輸入行 → currentInput 事件（prompt 符號後的部分才是使用者輸入）
    private func currentInputEvent(from raw: String) -> ParserEvent {
        if let promptRange = Self.promptSymbolRange(in: raw) {
            let typed = String(raw[promptRange.upperBound...])
            return .currentInput(text: typed)
        }
        return .currentInput(text: raw)
    }

    // MARK: - Heuristics

    /// 找 prompt 結尾符號（% / $ / #）的位置；找不到回 nil
    private static func promptSymbolRange(in line: String) -> Range<String.Index>? {
        // 優先抓 "user@host ... % " 這種完整 prompt 的結尾符號
        line.range(of: #"[%$#]\s?"#, options: .regularExpression)
    }

    /// 是否為 prompt 行：含 user@host，或結尾是 prompt 符號
    private func isPromptLine(_ line: String) -> Bool {
        line.range(of: #"\S+@\S+"#, options: .regularExpression) != nil
            || AnsiStripper.isPromptLine(line)
    }

    /// 從 prompt 前綴解析路徑（例如 "smallfire@host ~ %" → "~"）
    private static func extractPath(fromPromptPrefix prefix: String) -> String? {
        AnsiStripper.extractPath(from: prefix)
    }
}
