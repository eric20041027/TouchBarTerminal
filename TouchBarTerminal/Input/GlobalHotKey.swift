import Carbon

/// 包裝 Carbon RegisterEventHotKey，用於全域熱鍵 (⌃⌥Space)
final class GlobalHotKey {

    struct Modifier: OptionSet {
        let rawValue: UInt32
        static let control = Modifier(rawValue: UInt32(controlKey))
        static let option  = Modifier(rawValue: UInt32(optionKey))
        static let shift   = Modifier(rawValue: UInt32(shiftKey))
        static let command = Modifier(rawValue: UInt32(cmdKey))
    }

    private var hotKeyRef: EventHotKeyRef?
    private let action: () -> Void
    private static var handlers: [UInt32: () -> Void] = [:]
    private static var nextID: UInt32 = 1

    init(keyCode: UInt32, modifiers: Modifier, action: @escaping () -> Void) {
        self.action = action
        let id = Self.nextID
        Self.nextID += 1
        Self.handlers[id] = action

        var hotKeyID = EventHotKeyID(signature: OSType("TBT\0".utf8.reduce(0) { $0 << 8 | UInt32($1) }),
                                     id: id)
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ -> OSStatus in
                var hkID = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                  EventParamType(typeEventHotKeyID), nil,
                                  MemoryLayout<EventHotKeyID>.size, nil, &hkID)
                GlobalHotKey.handlers[hkID.id]?()
                return noErr
            },
            1, &eventType, nil, nil
        )

        RegisterEventHotKey(keyCode, modifiers.rawValue, hotKeyID,
                            GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    deinit {
        if let ref = hotKeyRef { UnregisterEventHotKey(ref) }
    }
}
