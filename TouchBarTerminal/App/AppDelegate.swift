import AppKit

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItemController: StatusItemController?
    private var touchBarController: TouchBarController?
    private var terminalSession: TerminalSession?
    private var globalHotKey: GlobalHotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("🚀 App launched")
        
        NSApp.setActivationPolicy(.accessory)
        print("✅ Activation policy set")

        let session = TerminalSession()
        self.terminalSession = session

        let tbController = TouchBarController(session: session)
        self.touchBarController = tbController

        self.statusItemController = StatusItemController(session: session)
        print("✅ StatusItemController created")

        NSApp.touchBar = tbController.makeTouchBar()
        print("✅ TouchBar assigned")

        self.globalHotKey = GlobalHotKey(keyCode: 49, modifiers: [.control, .option]) { [weak self] in
            self?.toggleFocus()
        }
        
        // 啟動 session（Phase 1 測試資料）
        session.start()

        print("✅ Done launching")
    }

    func applicationWillTerminate(_ notification: Notification) {
        terminalSession?.stop()
    }

    private func toggleFocus() {
        if NSApp.isActive {
            NSApp.hide(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
