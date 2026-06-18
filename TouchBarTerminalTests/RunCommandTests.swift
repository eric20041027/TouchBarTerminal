import XCTest
@testable import TouchBarTerminal

/// git 按鈕送出的指令位元組序列（純邏輯，與 PTY I/O 分離）。
///
/// `runCommand` 會先送 ⌃U（0x15）清掉 zsh 行內殘留，再送指令本體 + 換行，
/// 確保使用者正在打到一半的 buffer 不會跟按鈕指令混在一起。
final class RunCommandTests: XCTestCase {

    // ⌃U（0x15）開頭：先清掉 zsh 目前行的殘留
    func test_commandBytes_starts_with_ctrl_u() {
        let bytes = TerminalSession.commandBytes(for: "git status -sb")
        XCTAssertEqual(bytes.first, 0x15)
    }

    // 指令本體完整保留，並以換行（\n = 0x0a）結尾觸發執行
    func test_commandBytes_contains_command_and_newline() {
        let bytes = TerminalSession.commandBytes(for: "git push")
        let expected = Data([0x15]) + Data("git push\n".utf8)
        XCTAssertEqual(bytes, expected)
    }

    // 空指令也補換行（等同送一個 Enter，不會 crash）
    func test_commandBytes_empty_command() {
        let bytes = TerminalSession.commandBytes(for: "")
        XCTAssertEqual(bytes, Data([0x15]) + Data("\n".utf8))
    }
}
