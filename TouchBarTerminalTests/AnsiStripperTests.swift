import XCTest
@testable import TouchBarTerminal
final class AnsiStripperTests: XCTestCase {

    func test_strip_color_codes() {
        let input = "\u{1B}[0;32mhello\u{1B}[0m"
        XCTAssertEqual(AnsiStripper.strip(input), "hello")
    }

    func test_strip_cursor_movement() {
        let input = "\u{1B}[2Jhello"
        XCTAssertEqual(AnsiStripper.strip(input), "hello")
    }

    func test_plain_text_unchanged() {
        XCTAssertEqual(AnsiStripper.strip("hello world"), "hello world")
    }

    func test_last_meaningful_line() {
        let raw = "\u{1B}[0mfoo\nbar\n\n"
        XCTAssertEqual(AnsiStripper.lastMeaningfulLine(from: raw), "bar")
    }

    func test_is_prompt_line() {
        XCTAssertTrue(AnsiStripper.isPromptLine("user@host % "))
        XCTAssertTrue(AnsiStripper.isPromptLine("$ "))
        XCTAssertFalse(AnsiStripper.isPromptLine("hello world"))
    }
}
