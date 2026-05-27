import Foundation

/// 環狀命令歷史緩衝，容量 100
struct CommandHistory {

    private static let capacity = 100
    private var items: [String] = []
    private var cursor: Int = -1   // -1 = 目前在最新位置

    mutating func push(_ command: String) {
        guard !command.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        // 避免連續重複
        if items.last == command { cursor = -1; return }
        if items.count >= Self.capacity { items.removeFirst() }
        items.append(command)
        cursor = -1
    }

    /// 返回上一條歷史（↑）
    mutating func previous() -> String? {
        guard !items.isEmpty else { return nil }
        if cursor == -1 {
            cursor = items.count - 1
        } else if cursor > 0 {
            cursor -= 1
        }
        return items[cursor]
    }

    /// 返回下一條歷史（↓），回到最新回傳 nil
    mutating func next() -> String? {
        guard cursor != -1 else { return nil }
        if cursor < items.count - 1 {
            cursor += 1
            return items[cursor]
        } else {
            cursor = -1
            return nil
        }
    }

    var count: Int { items.count }
}
