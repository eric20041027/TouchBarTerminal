import Carbon
import AppKit

/// 用 Carbon RegisterEventHotKey 註冊全域熱鍵
final class GlobalHotKey {

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let action: () -> Void

    // 用一個靜態字典把 hotkey id 對應到 callback
    private static var handlers: [UInt32: () -> Void] = [:]
    private static var nextID: UInt32 = 1
    private let myID: UInt32

    init(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        self.action = action
        self.myID = Self.nextID
        Self.nextID += 1
        Self.handlers[myID] = action

        // 1. 安裝事件處理器（整個 App 只需一次，但這裡簡化每個 hotkey 各裝一次）
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ -> OSStatus in
                var hkID = EventHotKeyID()
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hkID
                )
                // 在主執行緒呼叫對應的 callback
                DispatchQueue.main.async {
                    GlobalHotKey.handlers[hkID.id]?()
                }
                return noErr
            },
            1,
            &eventType,
            nil,
            &eventHandler
        )

        // 2. 註冊熱鍵
        let hotKeyID = EventHotKeyID(signature: OSType(0x54425431), id: myID)  // 'TBT1'
        RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    deinit {
        if let ref = hotKeyRef { UnregisterEventHotKey(ref) }
        Self.handlers[myID] = nil
    }
}
