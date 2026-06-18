import Foundation

/// 動態橋接 DFRFoundation 的私有函式，控制系統 Control Strip 的顯示。
///
/// `DFRElementSetControlStripPresenceForIdentifier` 等函式不在公開 SDK，
/// 用 dlopen/dlsym 在執行期取得。隱藏 Control Strip 才能讓
/// system modal Touch Bar 真正佔滿整條。
enum DFR {

    // DFRElementSetControlStripPresenceForIdentifier(CFString identifier, Bool present)
    private typealias SetElementPresenceFn = @convention(c) (CFString, Bool) -> Void

    private static let setElementPresenceFn: SetElementPresenceFn? = {
        let rtldDefault = UnsafeMutableRawPointer(bitPattern: -2)
        guard let sym = dlsym(rtldDefault, "DFRElementSetControlStripPresenceForIdentifier") else {
            return nil
        }
        return unsafeBitCast(sym, to: SetElementPresenceFn.self)
    }()

    /// 顯示（true）或隱藏（false）系統 Control Strip。
    /// 對每個系統 Control Strip 元件 identifier 設定 presence。
    static func setControlStripPresence(_ visible: Bool) {
        // 系統 Control Strip 的標準元件 identifiers
        let identifiers: [CFString] = [
            "com.apple.system.brightness" as CFString,
            "com.apple.system.volume" as CFString,
            "com.apple.system.mute" as CFString,
            "com.apple.system.siri" as CFString,
            "com.apple.system.group.brightness" as CFString,
            "com.apple.system.group.media" as CFString,
        ]
        for id in identifiers {
            setElementPresenceFn?(id, visible)
        }
    }
}
