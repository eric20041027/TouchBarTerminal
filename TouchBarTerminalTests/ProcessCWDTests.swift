import XCTest
import Darwin
@testable import TouchBarTerminal

final class ProcessCWDTests: XCTestCase {

    // 查自己行程的 cwd → 應等於 FileManager 報告的當前目錄
    func test_returns_own_cwd() {
        let pid = getpid()
        let cwd = ProcessCWD.of(pid: pid)
        XCTAssertNotNil(cwd)
        XCTAssertEqual(cwd, FileManager.default.currentDirectoryPath)
    }

    // 不存在的 pid → nil
    func test_invalid_pid_returns_nil() {
        XCTAssertNil(ProcessCWD.of(pid: -1))
        XCTAssertNil(ProcessCWD.of(pid: 0))
    }
}
