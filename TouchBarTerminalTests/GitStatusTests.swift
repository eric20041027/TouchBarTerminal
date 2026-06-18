import XCTest
@testable import TouchBarTerminal

final class GitStatusTests: XCTestCase {

    // MARK: - branchName(fromHEAD:) 純邏輯

    // 一般分支：ref: refs/heads/main → "main"
    func test_branch_from_normal_HEAD() {
        XCTAssertEqual(GitStatus.branchName(fromHEAD: "ref: refs/heads/main\n"), "main")
    }

    // 分支名含斜線：ref: refs/heads/feature/login → "feature/login"
    func test_branch_with_slash() {
        XCTAssertEqual(
            GitStatus.branchName(fromHEAD: "ref: refs/heads/feature/login\n"),
            "feature/login"
        )
    }

    // detached HEAD（直接是 commit hash）→ 顯示短 hash
    func test_detached_HEAD_shows_short_hash() {
        XCTAssertEqual(
            GitStatus.branchName(fromHEAD: "4a3f2e1b9c8d7e6f5a4b3c2d1e0f9a8b7c6d5e4f\n"),
            "4a3f2e1"
        )
    }

    // 空內容 → nil
    func test_empty_HEAD_returns_nil() {
        XCTAssertNil(GitStatus.branchName(fromHEAD: ""))
        XCTAssertNil(GitStatus.branchName(fromHEAD: "   \n"))
    }

    // MARK: - detect(at:) 檔案系統整合

    // 在臨時建立的假 repo（含 .git/HEAD）偵測 → 是 repo，分支正確
    func test_detect_in_fake_repo() throws {
        let fm = FileManager.default
        let repo = NSTemporaryDirectory() + "gitstatus-\(UUID().uuidString)"
        try fm.createDirectory(atPath: repo + "/.git", withIntermediateDirectories: true)
        try "ref: refs/heads/develop\n".write(
            toFile: repo + "/.git/HEAD", atomically: true, encoding: .utf8
        )
        defer { try? fm.removeItem(atPath: repo) }

        let result = GitStatus.detect(at: repo)
        XCTAssertTrue(result.isRepo)
        XCTAssertEqual(result.branch, "develop")
    }

    // 子目錄也算在 repo 內（往上找 .git）
    func test_detect_in_repo_subdirectory() throws {
        let fm = FileManager.default
        let repo = NSTemporaryDirectory() + "gitstatus-\(UUID().uuidString)"
        let sub = repo + "/src/deep"
        try fm.createDirectory(atPath: repo + "/.git", withIntermediateDirectories: true)
        try fm.createDirectory(atPath: sub, withIntermediateDirectories: true)
        try "ref: refs/heads/main\n".write(
            toFile: repo + "/.git/HEAD", atomically: true, encoding: .utf8
        )
        defer { try? fm.removeItem(atPath: repo) }

        let result = GitStatus.detect(at: sub)
        XCTAssertTrue(result.isRepo)
        XCTAssertEqual(result.branch, "main")
    }

    // 非 repo 的臨時空目錄 → 不是 repo
    func test_detect_in_non_repo() throws {
        let fm = FileManager.default
        let dir = NSTemporaryDirectory() + "norepo-\(UUID().uuidString)"
        try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: dir) }

        let result = GitStatus.detect(at: dir)
        XCTAssertFalse(result.isRepo)
        XCTAssertNil(result.branch)
    }
}
