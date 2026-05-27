import Foundation

/// 剝除 ANSI/VT100 escape sequence，回傳純文字
enum AnsiStripper {

    // CSI sequences: ESC [ ... 最終字元
    // OSC sequences: ESC ] ... ST 或 BEL
    private static let pattern = #"\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~]|\][^\x07\x1B]*(?:\x07|\x1B\\))"#

    private static let regex: NSRegularExpression = {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: pattern, options: [])
    }()

    static func strip(_ input: String) -> String {
        let range = NSRange(input.startIndex..., in: input)
        return regex.stringByReplacingMatches(in: input, range: range, withTemplate: "")
    }

    /// 從多行輸出中取出最後一個非空行
    static func lastMeaningfulLine(from raw: String) -> String? {
        let stripped = strip(raw)
        return stripped
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .last { !$0.isEmpty }
    }

    /// 簡易 prompt 偵測：以 $ / % / # + 空格結尾
    static func isPromptLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasSuffix("$ ") || trimmed.hasSuffix("% ") || trimmed.hasSuffix("# ")
    }
}
