import Foundation

enum AnsiStripper {

    // 剝除 ANSI escape sequence 的 regex
    private static let regex: NSRegularExpression = {
        let pattern = #"\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])"#
        return try! NSRegularExpression(pattern: pattern)
    }()

    /// 剝除 ANSI codes，回傳純文字
    static func strip(_ input: String) -> String {
        let range = NSRange(input.startIndex..., in: input)
        return regex.stringByReplacingMatches(in: input, range: range, withTemplate: "")
    }

    /// 從多行輸出取最後一個非空行
    static func lastMeaningfulLine(from raw: String) -> String? {
        let stripped = strip(raw)
        return stripped
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .last { !$0.isEmpty }
    }
    /// 簡易 prompt 偵測：以 $ / % / # 結尾
    static func isPromptLine(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        return t.hasSuffix("$ ") || t.hasSuffix("% ") || t.hasSuffix("# ")
            || t.hasSuffix("$") || t.hasSuffix("%") || t.hasSuffix("#")
    }

    /// 從 prompt 解析目前路徑
    /// 例如 "(base) smallfire@pongpong-3 ~ %" → "~"
    static func extractPath(from prompt: String) -> String? {
        // 取結尾 % / $ / # 前面那個「非空白詞」當作路徑
        let pattern = #"(\S+)\s+[%$#]\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(prompt.startIndex..., in: prompt)
        guard let match = regex.firstMatch(in: prompt, range: range),
              let r = Range(match.range(at: 1), in: prompt) else {
            return nil
        }
        return String(prompt[r])
    }
}
