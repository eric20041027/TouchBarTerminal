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
}
