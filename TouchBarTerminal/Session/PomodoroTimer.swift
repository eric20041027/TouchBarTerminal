import Foundation

/// 番茄鐘的純邏輯狀態機（不碰 Timer / UI，方便單元測試）。
///
/// 外部每秒呼叫 `tick()` 推進；`start()` / `stop()` 控制。
/// 衍生出 `remainingSeconds`、`progress`（0…1）、`displayText`（`MM:SS`）。
struct PomodoroTimer {

    enum State {
        case idle       // 未開始
        case running    // 倒數中
        case finished   // 到點
    }

    private let durationSeconds: Int
    private(set) var state: State = .idle
    private(set) var remainingSeconds: Int

    init(durationSeconds: Int) {
        self.durationSeconds = durationSeconds
        self.remainingSeconds = durationSeconds
    }

    /// 已過進度，0（剛開始/未開始）→ 1（到點）。
    var progress: Double {
        guard durationSeconds > 0 else { return 0 }
        return Double(durationSeconds - remainingSeconds) / Double(durationSeconds)
    }

    /// `MM:SS` 顯示字串（秒補零）。
    var displayText: String {
        let minutes = remainingSeconds / 60
        let seconds = remainingSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    /// 開始倒數（從滿開始）。
    mutating func start() {
        state = .running
        remainingSeconds = durationSeconds
    }

    /// 推進一秒（只在 running 有效）；到 0 轉 finished。
    mutating func tick() {
        guard state == .running else { return }
        remainingSeconds = max(0, remainingSeconds - 1)
        if remainingSeconds == 0 {
            state = .finished
        }
    }

    /// 停止並重置回 idle（滿）。
    mutating func stop() {
        state = .idle
        remainingSeconds = durationSeconds
    }
}
