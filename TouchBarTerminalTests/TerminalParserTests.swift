import XCTest
@testable import TouchBarTerminal

/// TerminalParser 的單元測試。
/// 每個 case 對應一個我們實際遇過的 bug，鎖死行為避免回歸。
final class TerminalParserTests: XCTestCase {

    // 一般字元即時 echo → currentInput
    func test_typing_emits_currentInput() {
        var parser = TerminalParser()
        let events = parser.feed("ls")
        XCTAssertEqual(events.last, .currentInput(text: "ls"))
    }

    // Backspace echo 刪掉最後一字
    func test_backspace_removes_last_char() {
        var parser = TerminalParser()
        _ = parser.feed("ls")
        let events = parser.feed("\u{7f}")
        XCTAssertEqual(events.last, .currentInput(text: "l"))
    }

    // 純輸出行（不含 prompt）→ output 事件
    func test_plain_output_line() {
        var parser = TerminalParser()
        let events = parser.feed("hello world\n")
        XCTAssertTrue(events.contains(.output(line: "hello world")))
    }

    // prompt 行 → 解析路徑，不當輸出
    func test_prompt_line_extracts_path_not_output() {
        var parser = TerminalParser()
        let events = parser.feed("smallfire@pongpong-3 ~ %\n")
        XCTAssertTrue(events.contains(.prompt(path: "~")))
        XCTAssertFalse(events.contains { if case .output = $0 { return true }; return false })
    }

    // Bug：prompt 與指令黏在一起（"%pwd"）不該變成輸出
    func test_prompt_with_glued_command_not_output() {
        var parser = TerminalParser()
        let events = parser.feed("smallfire@pongpong-3 ~ %pwd\n")
        // 應解析出路徑，且不把 "pwd" 當輸出
        XCTAssertTrue(events.contains(.prompt(path: "~")))
        XCTAssertFalse(events.contains(.output(line: "pwd")))
    }

    // Bug：user@host 回顯行不該進右側輸出
    func test_userhost_echo_not_output() {
        var parser = TerminalParser()
        let events = parser.feed("smallfire@pongpong-3 ~ ll\n")
        XCTAssertFalse(events.contains(.output(line: "smallfire@pongpong-3 ~ ll")))
    }

    // \r\n 與單獨 \r 都當行結束，不黏行
    func test_crlf_splits_lines() {
        var parser = TerminalParser()
        let events = parser.feed("foo\r\nbar\n")
        XCTAssertTrue(events.contains(.output(line: "foo")))
        XCTAssertTrue(events.contains(.output(line: "bar")))
    }

    // ANSI 色碼被剝除
    func test_ansi_stripped_from_output() {
        var parser = TerminalParser()
        let events = parser.feed("\u{1B}[0;32mgreen\u{1B}[0m\n")
        XCTAssertTrue(events.contains(.output(line: "green")))
    }

    // 偵測 sudo 密碼提示 → passwordPrompt 事件
    func test_detects_password_prompt() {
        var parser = TerminalParser()
        let events = parser.feed("Password:")
        XCTAssertTrue(events.contains { if case .passwordPrompt = $0 { return true }; return false })
        XCTAssertTrue(parser.inPasswordMode)
    }

    // 看到一般 prompt → 離開密碼模式
    func test_password_ends_on_shell_prompt() {
        var parser = TerminalParser()
        _ = parser.feed("Password:")
        let events = parser.feed("\nsmallfire@host ~ %\n")
        XCTAssertTrue(events.contains(.passwordEnded))
        XCTAssertFalse(parser.inPasswordMode)
    }


    // Bug 修復：cd 後新 prompt 不換行（卡 buffer）也要即時解析路徑
    func test_prompt_without_newline_extracts_path() {
        var parser = TerminalParser()
        let events = parser.feed("smallfire@pongpong-3 Desktop % ")
        XCTAssertTrue(events.contains(.prompt(path: "Desktop")))
    }

}
