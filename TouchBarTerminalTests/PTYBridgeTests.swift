import XCTest
@testable import TouchBarTerminal

/// PTY 整合測試（Phase 2 起才能真正跑）
final class PTYBridgeTests: XCTestCase {

    func test_placeholder_until_phase2() {
        // TODO Phase 2: fork PTY, write "echo hi\n", assert output contains "hi"
        XCTAssertTrue(true, "placeholder")
    }
}
