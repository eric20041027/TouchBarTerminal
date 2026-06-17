import Foundation

/// 本地路徑補全。
///
/// 不依賴 zsh，自己用 FileManager 列檔案，避免雙向同步的纏結。
/// 補全 buffer 最後一個 token（多半是路徑），對「補目錄/檔名」這個
/// 最常見場景完全夠用。
enum PathCompleter {

    enum Result: Equatable {
        /// 唯一結果 → 直接補進 buffer
        case unique(completedBuffer: String)
        /// 多個候選 → 顯示給使用者，不動 buffer
        case candidates([String])
        /// 無符合
        case none
    }

    /// 對整行指令做補全，cwd 是目前工作目錄（可為 ~ 開頭，會自動展開）。
    static func complete(_ buffer: String, cwd rawCwd: String) -> Result {
        // cwd 可能是 prompt 顯示的 "~" 或 "~/foo"，先展開成絕對路徑，
        // 否則 contentsOfDirectory(atPath:) 找不到目錄。
        let cwd = (rawCwd as NSString).expandingTildeInPath
        // 取最後一個 token（以空白切）
        let parts = buffer.split(separator: " ", omittingEmptySubsequences: false)
        guard let lastToken = parts.last.map(String.init), !lastToken.isEmpty else {
            return .none
        }

        // 拆出目錄前綴與待補名稱：如 "Desktop/Doc" → dir="Desktop", partial="Doc"
        let expanded = (lastToken as NSString).expandingTildeInPath
        let dirPart = (expanded as NSString).deletingLastPathComponent
        let partial = (expanded as NSString).lastPathComponent

        let searchDir: String
        if dirPart.isEmpty {
            searchDir = cwd
        } else if dirPart.hasPrefix("/") {
            searchDir = dirPart
        } else {
            searchDir = (cwd as NSString).appendingPathComponent(dirPart)
        }

        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: searchDir) else {
            return .none
        }

        let matches = entries
            .filter { $0.hasPrefix(partial) && !$0.hasPrefix(".") }
            .sorted()

        switch matches.count {
        case 0:
            return .none
        case 1:
            // 唯一 → 補完整。把 buffer 最後 token 換成補全後的路徑。
            let completedToken = replaceLastComponent(in: lastToken, with: matches[0])
            let prefix = parts.dropLast().joined(separator: " ")
            let completed = prefix.isEmpty ? completedToken : prefix + " " + completedToken
            return .unique(completedBuffer: completed)
        default:
            return .candidates(matches)
        }
    }

    /// 把 token 的最後一段換成 name，保留前面的目錄結構與 ~ 前綴
    private static func replaceLastComponent(in token: String, with name: String) -> String {
        let dir = (token as NSString).deletingLastPathComponent
        if dir.isEmpty {
            return name
        }
        return (dir as NSString).appendingPathComponent(name)
    }
}
