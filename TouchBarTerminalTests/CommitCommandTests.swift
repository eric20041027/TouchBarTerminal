import XCTest
@testable import TouchBarTerminal

/// commit 按鈕的 message → `git commit -m "..."` 指令組裝（純邏輯）。
///
/// 訊息由使用者在左側臨時輸入框打進來，可能含雙引號等特殊字元，
/// 必須正確跳脫，避免 shell 把指令拆壞或注入。
final class CommitCommandTests: XCTestCase {

    // 一般訊息 → git commit -m "fix bug"
    func test_normal_message() {
        XCTAssertEqual(
            TerminalSession.commitCommand(message: "fix bug"),
            #"git commit -m "fix bug""#
        )
    }

    // 訊息含雙引號 → 跳脫成 \"，避免拆壞指令
    func test_message_with_double_quote() {
        XCTAssertEqual(
            TerminalSession.commitCommand(message: #"add "smart" mode"#),
            #"git commit -m "add \"smart\" mode""#
        )
    }

    // 訊息含反斜線 → 先跳脫反斜線本身（避免 \" 被誤解）
    func test_message_with_backslash() {
        XCTAssertEqual(
            TerminalSession.commitCommand(message: #"path\to"#),
            #"git commit -m "path\\to""#
        )
    }

    // 前後空白修掉（避免送出純空白訊息）
    func test_trims_whitespace() {
        XCTAssertEqual(
            TerminalSession.commitCommand(message: "  hello  "),
            #"git commit -m "hello""#
        )
    }
}
