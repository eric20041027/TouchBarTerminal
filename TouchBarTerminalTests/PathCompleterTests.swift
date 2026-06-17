import XCTest
@testable import TouchBarTerminal

/// PathCompleter 的單元測試。
/// 在臨時目錄建立可預期的檔案結構，驗證補全行為。
final class PathCompleterTests: XCTestCase {

    private var tmpDir: String!

    override func setUpWithError() throws {
        // 建立臨時目錄與測試檔案
        tmpDir = NSTemporaryDirectory() + "pathcompleter-\(UUID().uuidString)"
        let fm = FileManager.default
        try fm.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)
        try fm.createDirectory(atPath: tmpDir + "/Desktop", withIntermediateDirectories: true)
        try fm.createDirectory(atPath: tmpDir + "/Documents", withIntermediateDirectories: true)
        try fm.createDirectory(atPath: tmpDir + "/Downloads", withIntermediateDirectories: true)
        fm.createFile(atPath: tmpDir + "/uniquefile.txt", contents: nil)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(atPath: tmpDir)
    }

    // 唯一前綴 → 補完整
    func test_unique_prefix_completes() {
        let result = PathCompleter.complete("cd Desk", cwd: tmpDir)
        XCTAssertEqual(result, .unique(completedBuffer: "cd Desktop"))
    }

    // 多個符合 → 回候選清單
    func test_multiple_matches_returns_candidates() {
        let result = PathCompleter.complete("cd D", cwd: tmpDir)
        guard case .candidates(let list) = result else {
            return XCTFail("expected candidates, got \(result)")
        }
        XCTAssertEqual(list, ["Desktop", "Documents", "Downloads"])
    }

    // 無符合 → none
    func test_no_match_returns_none() {
        let result = PathCompleter.complete("cd zzz", cwd: tmpDir)
        XCTAssertEqual(result, .none)
    }

    // 唯一檔案前綴
    func test_unique_file_completes() {
        let result = PathCompleter.complete("cat uni", cwd: tmpDir)
        XCTAssertEqual(result, .unique(completedBuffer: "cat uniquefile.txt"))
    }

    // 空 buffer → none
    func test_empty_buffer_returns_none() {
        let result = PathCompleter.complete("", cwd: tmpDir)
        XCTAssertEqual(result, .none)
    }
}
