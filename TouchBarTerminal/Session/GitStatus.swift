import Foundation

/// 偵測目錄是否為 git repo，並取得當前分支。
///
/// 純邏輯（解析 `.git/HEAD` 內容）與檔案存取分離，方便測試：
/// - `branchName(fromHEAD:)` 是純函式
/// - `detect(at:)` 碰檔案系統，組合純函式
enum GitStatus {

    struct Result: Equatable {
        let isRepo: Bool
        let branch: String?

        static let notARepo = Result(isRepo: false, branch: nil)
    }

    /// 從 `.git/HEAD` 內容解析分支名。
    /// - "ref: refs/heads/main"  → "main"
    /// - "<40 字元 commit hash>"  → 短 hash（detached HEAD）
    /// - 空 → nil
    static func branchName(fromHEAD head: String) -> String? {
        let trimmed = head.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let refPrefix = "ref: refs/heads/"
        if trimmed.hasPrefix(refPrefix) {
            return String(trimmed.dropFirst(refPrefix.count))
        }
        // detached HEAD：直接是 commit hash → 取前 7 碼
        return String(trimmed.prefix(7))
    }

    /// 偵測指定目錄是否為 git repo（含分支）。
    /// 從該目錄往上找 `.git/HEAD`（git 子目錄也算在 repo 內）。
    static func detect(at directory: String) -> Result {
        let fm = FileManager.default
        var dir = (directory as NSString).standardizingPath

        while !dir.isEmpty && dir != "/" {
            let headPath = (dir as NSString)
                .appendingPathComponent(".git")
                .appending("/HEAD")
            if let content = try? String(contentsOfFile: headPath, encoding: .utf8) {
                return Result(isRepo: true, branch: branchName(fromHEAD: content))
            }
            dir = (dir as NSString).deletingLastPathComponent
        }
        return .notARepo
    }
}
