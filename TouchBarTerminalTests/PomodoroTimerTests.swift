import XCTest
@testable import TouchBarTerminal

/// 番茄鐘純邏輯狀態機（不碰 Timer / UI，可完全離線測試）。
///
/// 狀態：idle（未開始）→ running（倒數中）→ finished（到點）。
/// 由外部每秒呼叫 tick() 推進；start/stop 控制；衍生出剩餘秒數、進度、顯示字串。
final class PomodoroTimerTests: XCTestCase {

    // MARK: - 初始狀態

    func test_initial_state_is_idle() {
        let timer = PomodoroTimer(durationSeconds: 1500)   // 25 分鐘
        XCTAssertEqual(timer.state, .idle)
        XCTAssertEqual(timer.remainingSeconds, 1500)
        XCTAssertEqual(timer.progress, 0)            // 還沒開始，進度 0
        XCTAssertEqual(timer.displayText, "25:00")
    }

    // MARK: - start / tick

    func test_start_enters_running() {
        var timer = PomodoroTimer(durationSeconds: 1500)
        timer.start()
        XCTAssertEqual(timer.state, .running)
        XCTAssertEqual(timer.remainingSeconds, 1500)
    }

    func test_tick_decrements_remaining() {
        var timer = PomodoroTimer(durationSeconds: 1500)
        timer.start()
        timer.tick()
        XCTAssertEqual(timer.remainingSeconds, 1499)
        XCTAssertEqual(timer.displayText, "24:59")
    }

    // idle 狀態 tick 不該動（還沒開始）
    func test_tick_when_idle_does_nothing() {
        var timer = PomodoroTimer(durationSeconds: 1500)
        timer.tick()
        XCTAssertEqual(timer.remainingSeconds, 1500)
        XCTAssertEqual(timer.state, .idle)
    }

    // MARK: - progress

    func test_progress_at_half() {
        var timer = PomodoroTimer(durationSeconds: 100)
        timer.start()
        for _ in 0..<50 { timer.tick() }
        XCTAssertEqual(timer.remainingSeconds, 50)
        XCTAssertEqual(timer.progress, 0.5, accuracy: 0.001)   // 已過一半
    }

    // MARK: - finish

    func test_reaches_finished_at_zero() {
        var timer = PomodoroTimer(durationSeconds: 3)
        timer.start()
        timer.tick(); timer.tick(); timer.tick()
        XCTAssertEqual(timer.remainingSeconds, 0)
        XCTAssertEqual(timer.state, .finished)
        XCTAssertEqual(timer.progress, 1.0, accuracy: 0.001)
    }

    // 到點後再 tick 不會變負數
    func test_tick_past_zero_stays_at_zero() {
        var timer = PomodoroTimer(durationSeconds: 1)
        timer.start()
        timer.tick(); timer.tick(); timer.tick()
        XCTAssertEqual(timer.remainingSeconds, 0)
        XCTAssertEqual(timer.state, .finished)
    }

    // MARK: - stop / reset

    func test_stop_resets_to_idle() {
        var timer = PomodoroTimer(durationSeconds: 1500)
        timer.start()
        timer.tick(); timer.tick()
        timer.stop()
        XCTAssertEqual(timer.state, .idle)
        XCTAssertEqual(timer.remainingSeconds, 1500)   // 回到滿
        XCTAssertEqual(timer.progress, 0)
    }

    // MARK: - displayText 格式

    func test_displayText_pads_seconds() {
        var timer = PomodoroTimer(durationSeconds: 65)
        XCTAssertEqual(timer.displayText, "01:05")
        timer.start()
        for _ in 0..<60 { timer.tick() }
        XCTAssertEqual(timer.displayText, "00:05")   // 秒補零
    }
}
