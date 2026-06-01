# Phase 0 講義：環境建置與專案骨架

## 學習目標
- 了解 macOS App 的基本結構
- 學會用 XcodeGen 管理 Xcode 專案
- 理解 `LSUIElement`（純 Menu Bar App）的概念

---

## 1. 工具鏈

| 工具 | 用途 | 安裝 |
|---|---|---|
| **Xcode** | Swift 開發環境、編譯器 | App Store |
| **XcodeGen** | 用 YAML 產生 `.xcodeproj`，避免 git 衝突 | `brew install xcodegen` |
| **Homebrew** | macOS 套件管理器（等同 pip/apt） | 官網一行指令 |

### 為什麼用 XcodeGen？

`.xcodeproj` 是一個複雜的 XML 檔案，多人協作時 git merge 幾乎一定衝突。
XcodeGen 讓你改 `project.yml`（純文字），再產生 `.xcodeproj`，解決這個問題。

```bash
# 每次新增/刪除 Swift 檔案後執行：
xcodegen generate
```

---

## 2. macOS App 類型

### 一般 App（有 Dock 圖示）
- 在 Dock 顯示圖示、有主視窗
- `LSUIElement = NO`（預設）

### Menu Bar App（純狀態列）
- **不顯示 Dock 圖示**，只在 menu bar 右上角有小圖示
- `LSUIElement = YES`（在 `Info.plist` 設定）

```xml
<!-- Info.plist -->
<key>LSUIElement</key>
<true/>
```

`LSUIElement` 是 Apple 的 Launch Services key。值為 `true` 時，App 以 "background-only" 模式啟動，不出現在 Dock 和 App Switcher（Cmd+Tab）。

---

## 3. Swift vs Python 基礎對照

```swift
// ── 變數宣告 ──
let name = "hello"   // let = 不可變（唯讀），宣告後不能再賦值
var count = 42       // var = 可變，可以重新賦值

// ── 類別宣告 ──
class AppDelegate: NSObject {
    // NSObject：幾乎所有 Apple Framework 物件都繼承它
    // 提供 ObjC runtime 基本功能（KVO、#selector 等）

    var session: TerminalSession?   // ? 表示這個屬性可能是 nil（Optional）

    init() {
        super.init()   // 必須呼叫父類別 init，Swift 規定
    }
}

// ── 函式宣告 ──
// _ notification：第一個參數的「外部標籤」是 _
// 代表呼叫時不需要寫參數名稱
// 例：applicationDidFinishLaunching(someNotification) 而非 applicationDidFinishLaunching(notification: someNotification)
func applicationDidFinishLaunching(_ notification: Notification) {
    print("App launched")
}
```

```python
# Python 對照
name = "hello"       # 沒有 let/var 區分，所有變數預設可變
count = 42

class AppDelegate:
    def __init__(self):
        self.session = None

    def application_did_finish_launching(self):
        print("App launched")
```

---

## 4. Optional（Swift 獨有）

Python 直接用 `None`，Swift 必須明確宣告「這個變數可能是 nil」：

```swift
var title: String? = nil
// String? 是 Optional<String> 的語法糖
// 意思是「這個值要麼是 String，要麼是 nil」
// Swift 不允許直接使用 Optional，必須先「解包（unwrap）」

title = "hello"

// ── 解包方式 1：if let（安全解包）──
if let t = title {
    print(t)   // 進到這裡，t 是確定有值的 String（不是 String?）
}
// title 是 nil 時，整個 if block 跳過

// ── 解包方式 2：?? 運算子（提供預設值）──
let display = title ?? "no title"
// title 有值 → display = title 的值
// title 是 nil → display = "no title"

// ── 解包方式 3：guard let（提早返回）──
func process() {
    guard let t = title else {
        return   // title 是 nil 就直接結束函式
    }
    print(t)   // 這裡 t 確定有值
}

// ── 解包方式 4：! 強制解包（危險！）──
print(title!)
// 確定有值時可用，title 是 nil 會立刻 crash（EXC_BAD_INSTRUCTION）
```

**為什麼這樣設計？** 強迫開發者處理「沒有值」的情況，避免 NullPointerException。

---

## 5. `@MainActor` — Swift 並發基礎

macOS UI **必須**在主執行緒（Main Thread）上操作。Swift 用 `@MainActor` 來保證這一點。

### 什麼是 Actor？

Actor 是 Swift Concurrency 的概念：一個 actor 內的程式碼保證「同一時間只有一個執行緒在跑」，避免 data race（兩個執行緒同時修改同一個值造成的錯誤）。

`@MainActor` 是特殊的全域 actor，代表「在主執行緒上執行」。

```swift
// ── class 標 @MainActor ──
// 效果：這個 class 的「所有方法和屬性存取」都保證在主執行緒
@MainActor
final class TouchBarController {
    var label: NSTextField = ...
    // 任何人呼叫 touchBarController.label，都一定在主執行緒
}

// ── function 標 @MainActor ──
// 效果：只有這個函式在主執行緒執行
@MainActor
func updateUI() {
    label.stringValue = "hello"
}

// ── 在 background thread 切回主執行緒 ──
Task { @MainActor in
    self.label.stringValue = "hello"   // 這段確保在主執行緒執行
}
```

**規則**：只要一個 class 用到 `@MainActor` 標記的東西，它自己也必須標 `@MainActor`。

常見錯誤訊息：
```
Main actor-isolated property 'xxx' can not be referenced from a nonisolated context
```
解法：在 class 宣告前加 `@MainActor`。

---

## 6. App 入口點：`main.swift`

Swift 有兩種 entry point 方式：

### 方式 A：`@main` 標記（簡單但有限制）
```swift
@main
class AppDelegate: NSObject, NSApplicationDelegate { ... }
// @main 告訴編譯器：這個 class 是 App 的起點
// 編譯器自動產生 main() 函式並呼叫這個 class
```

### 方式 B：`main.swift`（我們用這個）
```swift
// main.swift — 檔名一定要叫「main」，這是 Swift 的特殊規則
// Swift 編譯器看到 main.swift 就知道這是 top-level 程式碼的進入點
import AppKit

// MainActor.assumeIsolated：告訴 Swift「相信我，這裡已經在主執行緒」
// 因為 main.swift 的 top-level code 本來就在主執行緒執行
// 這個呼叫讓後面的 code 可以存取 @MainActor 標記的東西
MainActor.assumeIsolated {
    let delegate = AppDelegate()

    // NSApplication.shared：整個 App 只有一個 NSApplication（singleton）
    // .shared 取得這個唯一實例
    NSApplication.shared.delegate = delegate

    // NSApplicationMain：啟動 AppKit 的事件迴圈（run loop）
    // 這個呼叫「不會返回」，app 從此靠事件驅動
    // CommandLine.argc / unsafeArgv：把命令列參數傳入
    _ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
}
```

**為什麼用 B？** `@main` + `@MainActor` 會有初始化時序衝突，`main.swift` 更明確可控。

---

## 7. `NSApplicationDelegate` — App 生命週期

`AppDelegate` 遵守 `NSApplicationDelegate` 協定，AppKit 在特定時機自動呼叫對應方法：

```swift
class AppDelegate: NSObject, NSApplicationDelegate {

    // App 啟動完成後呼叫（所有初始化都在這裡做）
    func applicationDidFinishLaunching(_ notification: Notification) {
        // notification.object 是 NSApplication 實例
        // 在這裡初始化 session、controller 等物件
    }

    // App 即將結束時呼叫（清理資源）
    func applicationWillTerminate(_ notification: Notification) {
        session?.stop()
    }

    // 點 Dock 圖示重新打開時呼叫（Menu Bar App 通常不需要實作）
    func applicationShouldHandleReopen(_ sender: NSApplication,
                                       hasVisibleWindows flag: Bool) -> Bool {
        return false
    }
}
```

**Delegate 模式**：AppKit 讓你實作這些方法「勾進去」App 的生命週期，不需要繼承 NSApplication。這是 Apple Framework 的常見設計。

---

## 8. `Info.plist` 與 App Bundle

macOS App 是一個 `.app` 資料夾（Bundle），結構如下：

```
TouchBarTerminal.app/
└── Contents/
    ├── Info.plist      ← App 的設定檔（identifier、版本、LSUIElement 等）
    ├── MacOS/
    │   └── TouchBarTerminal  ← 實際的可執行檔（binary）
    └── Resources/      ← 圖片、字體等資源
```

`Info.plist` 重要的 key：

| Key | 說明 | 我們的值 |
|-----|------|---------|
| `CFBundleIdentifier` | App 唯一識別碼（reverse-DNS 格式） | `com.tbt.TouchBarTerminal` |
| `CFBundleName` | App 顯示名稱 | `TouchBarTerminal` |
| `LSUIElement` | 設為 `true` 隱藏 Dock 圖示 | `true` |
| `NSPrincipalClass` | AppKit 的主要 class | `NSApplication` |

---

## 9. `project.yml` — XcodeGen 設定詳解

```yaml
name: TouchBarTerminal          # 產生的 .xcodeproj 名稱

options:
  bundleIdPrefix: com.tbt       # Bundle ID 前綴，target 名會附在後面
                                # 最終 Bundle ID = com.tbt.TouchBarTerminal

targets:
  TouchBarTerminal:
    type: application           # 這是一個 app（不是 framework 或 test）
    platform: macOS
    deploymentTarget: "13.0"   # 最低支援 macOS 版本

    sources:
      - path: TouchBarTerminal  # XcodeGen 掃描這個資料夾裡所有 .swift 檔
                                # 不需要手動逐一新增，這是 XcodeGen 最大的優點

    info:
      path: Info.plist          # Info.plist 的位置
      properties:               # 也可以直接在 yml 裡寫 plist 內容
        LSUIElement: true
```

**為什麼每次新增檔案要 `xcodegen generate`？**
Xcode project 檔案記錄了所有源碼路徑，新增檔案後 `.xcodeproj` 還不知道這個檔案的存在，`xcodegen generate` 重新掃描並更新 project 設定。

---

## 10. 遇到的問題與解法

| 問題 | 原因 | 解法 |
|---|---|---|
| `@main` + `@MainActor` 衝突 | entry point 初始化時序問題 | 改用 `main.swift` + `MainActor.assumeIsolated` |
| App 啟動後什麼都沒有 | `applicationDidFinishLaunching` 沒被呼叫 | 確認 `delegate = delegate` 有設定 |
| Touch Bar 空白 | App 不是 frontmost | 點 menu bar 圖示讓 App 取得焦點 |
| `Main actor-isolated` 錯誤 | class 沒有標 `@MainActor` | 在 class 宣告前加 `@MainActor` |
| 新增 .swift 後 Xcode 找不到 | `.xcodeproj` 沒更新 | `xcodegen generate` 再 Load Changes |

---

## 11. 驗收標準

- [x] `⌘B` build 成功
- [x] `⌘R` 執行後 Dock **沒有**出現圖示
- [x] Menu bar 右上角出現 `⌨` 圖示
- [x] Console 看到 `🚀 App launched`
