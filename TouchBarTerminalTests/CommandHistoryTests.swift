import XCTest
@testable import TouchBarTerminal

final class CommandHistoryTests: XCTestCase {

    func test_push_increases_count() {
        var history = CommandHistory()
        history.push("ls")
        XCTAssertEqual(history.count, 1)
    }

    func test_previous_returns_last_command() {
        var history = CommandHistory()
        history.push("ls")
        history.push("pwd")
        XCTAssertEqual(history.previous(), "pwd")
        XCTAssertEqual(history.previous(), "ls")
    }

    func test_empty_command_ignored() {
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
