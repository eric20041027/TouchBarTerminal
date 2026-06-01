import AppKit

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {

    private var session: TerminalSession?
    private var touchBarController: TouchBarController?
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        print("🚀 App launched")

        // 建立核心物件
        let session = TerminalSession()
        self.session = session

        let tbController = TouchBarController(session: session)
        self.touchBarController = tbController

        self.statusItemController = StatusItemController(session: session)

        // 把 Touch Bar 掛到 App 層級
        NSApp.touchBar = tbController.makeTouchBar()

        // 啟動 session
        session.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        session?.stop()
    }
}
