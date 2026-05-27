import AppKit

@main
class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItemController: StatusItemController?
    private var touchBarController: TouchBarController?
    private var terminalSession: TerminalSession?
    private var globalHotKey: GlobalHotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 純 menu bar app：不顯示 Dock 圖示
        NSApp.setActivationPolicy(.accessory)

        // 建立核心物件
        let session = TerminalSession()
        self.terminalSession = session

        let tbController = TouchBarController(session: session)
        self.touchBarController = tbController

        self.statusItemController = StatusItemController(session: session)

        // 把 Touch Bar 掛到 application 層級
        NSApp.touchBar = tbController.makeTouchBar()

        // 全域熱鍵 ⌃⌥Space
        self.globalHotKey = GlobalHotKey(keyCode: 49, modifiers: [.control, .option]) { [weak self] in
            self?.toggleFocus()
        }

        // TODO Phase 2: session.start()
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
