import AppKit
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {

    private var session: TerminalSession?
    private var touchBarController: TouchBarController?
    private var statusItemController: StatusItemController?
    private var keyboardInterceptor: KeyboardInterceptor?  
    private var touchBar: NSTouchBar?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        print("🚀 App launched")

        let session = TerminalSession()
        self.session = session

        let tbController = TouchBarController(session: session)
        self.touchBarController = tbController

        self.statusItemController = StatusItemController(session: session)

        let tb = tbController.makeTouchBar()
        self.touchBar = tb
        NSApp.touchBar = tb

        session.start()

        // 建立並啟動鍵盤攔截
        let interceptor = KeyboardInterceptor(session: session)
        interceptor.start()
        self.keyboardInterceptor = interceptor
        // 監聽 App 重新取得焦點
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        keyboardInterceptor?.stop()  // 加這行
        session?.stop()
        
    }
    @objc private func appDidBecomeActive() {
        NSApp.touchBar = touchBar  // 重用同一個，不重新建立
        print("✅ App became active, Touch Bar restored")
    }
}
