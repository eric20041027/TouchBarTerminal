import AppKit
import Carbon
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {

    private var session: TerminalSession?
    private var touchBarController: TouchBarController?
    private var statusItemController: StatusItemController?
    private var keyboardInterceptor: KeyboardInterceptor?  
    private var touchBar: NSTouchBar?
    private var globalHotKey: GlobalHotKey?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        print("🚀 App launched")

        // 載入使用者設定（不存在則建立範本）
        let config = AppConfig.load()
        config.writeTemplateIfMissing()

        let session = TerminalSession(config: config)
        self.session = session

        let tbController = TouchBarController(session: session, fontSize: config.fontSize)
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
        
        // 全域熱鍵 ⌃⌥Space（keyCode 49 = Space）
        let ctrlOpt = UInt32(controlKey | optionKey)
        globalHotKey = GlobalHotKey(keyCode: 49, modifiers: ctrlOpt) { [weak self] in
            self?.toggleFocus()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        keyboardInterceptor?.stop()  // 加這行
        session?.stop()
        
    }
    
    @objc private func appDidBecomeActive() {
        NSApp.touchBar = touchBar  // 重用同一個，不重新建立
        print("✅ App became active, Touch Bar restored")
    }
    
    private func toggleFocus() {
        if NSApp.isActive {
            // 已經是前景 → 把焦點還給上一個 App
            NSApp.hide(nil)
        } else {
            // 不是前景 → 取得焦點，Touch Bar 變終端
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
