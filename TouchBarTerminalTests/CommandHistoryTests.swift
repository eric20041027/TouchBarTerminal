import XCTest
@testable import TouchBarTerminal

final class CommandHistoryTests: XCTestCase {

    func test_push_and_previous() {
        var history = CommandHistory()
        history.push("ls")
        history.push("pwd")
        XCTAssertEqual(history.previous(), "pwd")
        XCTAssertEqual(history.previous(), "ls")
    }

    func test_next_after_previous() {
        var history = CommandHistory()
        history.push("ls")
        history.push("pwd")
        _ = history.previous()
        _ = history.previous()
        XCTAssertEqual(history.next(), "pwd")
        XCTAssertNil(history.next())
    }

    func test_push_resets_cursor() {
        var history = CommandHistory()
        history.push("ls")
        _ = history.previous()
        history.push("pwd")
        XCTAssertEqual(history.previous(), "pwd")
    }

    func test_empty_push_ignored() {
        var history = CommandHistory()
        history.push("   ")
        XCTAssertEqual(history.count, 0)
    }

    func test_duplicate_consecutive_ignored() {
        var history = CommandHistory()
        history.push("ls")
        history.push("ls")
        XCTAssertEqual(history.count, 1)
    }
}
