# Phase 1 講義：Touch Bar 靜態渲染

## 學習目標
- 理解 NSTouchBar API 的結構
- 學會 NSStackView 版面配置
- 掌握 Combine 的 @Published / sink 資料綁定

---

## 1. NSTouchBar 架構

Touch Bar UI 的層次結構：

```
NSTouchBar                    ← 整條 Touch Bar 的容器
  └── NSCustomTouchBarItem    ← 一個「格子」
        └── NSView            ← 格子裡的內容（任何 NSView）
              └── NSStackView ← 我們用來垂直排列兩行文字
                    ├── NSTextField  ← 上排：輸出行
                    └── NSTextField  ← 下排：prompt + 輸入
```

### 關鍵 API

```swift
// 建立 Touch Bar
let bar = NSTouchBar()
bar.delegate = self                          // 誰來提供 items
bar.defaultItemIdentifiers = [.outputLine]   // 要顯示哪些 items

// 建立 Item（格子）
let item = NSCustomTouchBarItem(identifier: .outputLine)
item.view = myView   // 放入任何 NSView
```

### NSTouchBarDelegate

```swift
extension TouchBarController: NSTouchBarDelegate {
    func touchBar(_ touchBar: NSTouchBar,
                  makeItemForIdentifier identifier: NSTouchBarItem.Identifier) 
                  -> NSTouchBarItem? {
        switch identifier {
        case .outputLine: return outputItem
        default: return nil
        }
    }
}
```

---

## 2. NSStackView — 版面配置

類似 CSS flexbox，把多個 view 排成一排或一列：

```swift
let stack = NSStackView(views: [topLabel, bottomLabel])
stack.orientation = .vertical      // 垂直排列（.horizontal = 水平）
stack.spacing = 2                  // 元素間距 2pt
stack.distribution = .fillEqually  // 每個元素等高
stack.alignment = .leading         // 靠左對齊（重要！否則會置中）
stack.widthAnchor.constraint(equalToConstant: 600).isActive = true
```

### 常見陷阱：設定順序

```swift
// ❌ 錯誤：先把 view 加進 item，之後又設 translatesAutoresizingMaskIntoConstraints
outputItem.view = stack
label.translatesAutoresizingMaskIntoConstraints = false  // 造成 layout 遞迴！

// ✅ 正確：先設定所有屬性，最後才加進 item
label.translatesAutoresizingMaskIntoConstraints = false  // 不需要這行！
// NSStackView 自己管理子 view 的 constraints，不要手動設定
```

---

## 3. NSTextField — 文字顯示

```swift
let label = NSTextField(labelWithString: "")  // labelWithString = 唯讀文字
label.font = NSFont(name: "SFMono-Regular", size: 11) ?? NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
label.textColor = .white
label.backgroundColor = .clear
label.isBordered = false
label.isEditable = false
label.alignment = .left
label.stringValue = "顯示的文字"  // 更新文字
```

---

## 4. MVVM 架構

本專案採用 **MVVM（Model-View-ViewModel）** 架構：

```
Model          ViewModel           View
PTYBridge  →  TerminalSession  →  TouchBarController
（Shell）      （狀態管理）         （Touch Bar UI）
```

- **Model**：PTYBridge，管理真實的 shell 行程
- **ViewModel**：TerminalSession，持有 UI 需要的狀態（`@Published`）
- **View**：TouchBarController，訂閱 ViewModel 的狀態變化並更新 UI

---

## 5. Combine — 響應式資料綁定

Combine 是 Apple 的響應式框架，類似 Python 的 event/callback，但更系統化。

### @Published

```swift
class TerminalSession: ObservableObject {
    @Published var lastOutputLine: String = ""   // 這個值改變時，自動通知訂閱者
    @Published var inputBuffer: String = ""
}
```

### sink — 訂閱變化

```swift
session.$lastOutputLine           // $ 前綴 = 取得 Publisher
    .receive(on: DispatchQueue.main)   // 確保在主執行緒收到
    .sink { [weak self] newValue in    // 每次值改變都會呼叫這個 closure
        self?.outputLabel.stringValue = newValue
    }
    .store(in: &cancellables)     // 把訂閱存起來，否則會立刻被釋放
```

### [weak self] — 避免循環引用

```swift
// ❌ 危險：TouchBarController 持有 session，session 的 closure 又持有 TouchBarController
.sink { self.outputLabel.stringValue = newValue }

// ✅ 安全：用 weak self，如果 self 已被釋放就跳過
.sink { [weak self] newValue in
    self?.outputLabel.stringValue = newValue  // self? = 如果 self 是 nil 就不執行
}
```

---

## 6. NSStatusItem — Menu Bar 圖示

```swift
let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
statusItem.button?.title = "⌨"

let menu = NSMenu()
menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
statusItem.menu = menu
```

---

## 7. Touch Bar 顯示條件

`NSTouchBar` 只在以下條件同時成立時顯示：
1. **App 是 frontmost**（最前景）
2. **System Settings → Keyboard → Touch Bar shows = App Controls**
3. **App 有設定 `NSApp.touchBar`**

**LSUIElement App 取得焦點的方式：**
```swift
NSApp.activate(ignoringOtherApps: true)   // 讓 App 變成前景
NSApp.hide(nil)                            // 把焦點還給前一個 App
```

---

## 8. 遇到的問題與解法

| 問題 | 原因 | 解法 |
|---|---|---|
| Touch Bar 空白 | App 不是 frontmost | 點 menu bar 圖示取得焦點 |
| 文字跑到中間 | `principalItemIdentifier` 會置中 | 移除，改用 `widthAnchor` + `alignment = .leading` |
| layout 遞迴 warning | 在 stack 子 view 上設 `translatesAutoresizingMaskIntoConstraints` | 刪掉那行，NSStackView 自己管理 |
| Menu bar 沒圖示 | `StatusItemController` 沒初始化或被 ARC 釋放 | 確認 AppDelegate 有持有 `statusItemController` 的強引用 |

---

## 9. 驗收標準

- [x] Touch Bar 顯示兩行文字（上排輸出、下排 prompt）
- [x] 文字靠左對齊
- [x] 使用等寬字體（SF Mono）
- [x] Menu bar 有 `⌨` 圖示
- [x] 點圖示後 Touch Bar 出現內容

---

## 10. 實作順序與每個檔案的職責

### 建立順序
```
1. main.swift               → App 入口點
2. AppDelegate.swift        → App 生命週期管理
3. TerminalSession.swift    → ViewModel（狀態中心）
4. StatusItemController.swift → Menu Bar 圖示
5. TouchBarController.swift → Touch Bar UI
```

### 為什麼這個順序？
- `TerminalSession` 是核心，其他人都依賴它
- `StatusItemController` 和 `TouchBarController` 都需要 `TerminalSession` 才能初始化
- 最後才在 `AppDelegate` 把所有東西串起來

---

## 11. Set\<AnyCancellable\> — Combine 訂閱管理

```swift
private var cancellables = Set<AnyCancellable>()
```

Combine 的每個 `.sink` 訂閱會回傳一個 `AnyCancellable` token。
**必須把它存起來**，否則訂閱會立刻被釋放（等於沒訂閱）。

```swift
session.$isConnected
    .receive(on: DispatchQueue.main)
    .sink { [weak self] connected in
        self?.statusItem.button?.title = connected ? "⌨" : "⌨?"
    }
    .store(in: &cancellables)   // 存進 Set，跟著 class 生命週期
```

Python 類比：像 `addEventListener`，但你需要保留 handle 才能維持監聽狀態。

---

## 12. NSStatusItem — Menu Bar 圖示

```swift
let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
statusItem.button?.title = "⌨"

let menu = NSMenu()
menu.addItem(NSMenuItem(title: "TouchBarTerminal", action: nil, keyEquivalent: ""))
menu.addItem(.separator())
menu.addItem(NSMenuItem(
    title: "Quit",
    action: #selector(NSApplication.terminate(_:)),
    keyEquivalent: "q"
))
statusItem.menu = menu
```

### `#selector` 是什麼？
`#selector` 告訴系統「點選時要呼叫這個函式」。
`NSApplication.terminate(_:)` 是 macOS 內建的結束 App 函式。

---

## 13. final class 的意義

| | 說明 |
|---|---|
| `class` | 可以被繼承 |
| `final class` | 不能被繼承，編譯器可做最佳化 |

ViewModel 和 Controller 通常都標 `final`。

---

## 14. XcodeGen 工作流程

每次新增或刪除 Swift 檔案，都要：
```bash
xcodegen generate
```
然後在 Xcode 選 **Load Changes**。

**注意**：空資料夾不會出現在 Xcode 裡，資料夾裡至少要有一個檔案。

---

## 15. StatusItemController 完成

### 設計重點
- `init(session:)` — 依賴注入，由外部傳入 session，不自己建立
- `private func` — 內部細節隱藏，只有 `init` 對外
- `bindSession` 訂閱 `isConnected`：連線中顯示 `⌨`，斷線顯示 `⌨?`

### 依賴注入（Dependency Injection）
```swift
// ❌ 自己建立（緊耦合，難測試）
init() {
    let session = TerminalSession()  // 死綁在一起
}

// ✅ 由外部傳入（鬆耦合，易測試）
init(session: TerminalSession) {
    self.session = session           // 測試時可傳入假的 session
}
```

### private 存取控制
```swift
private let statusItem = ...    // 只有這個 class 能用
private var cancellables = ...  // 外部看不到
private func setupMenu() { }   // 內部實作細節

// 對外只暴露 init，其他全部隱藏
```

---

## 16. TouchBarController — 完整知識點

### 概覽
| 項目 | 說明 |
|---|---|
| 職責 | 建立 Touch Bar UI、訂閱 TerminalSession 狀態 |
| 繼承 | `NSObject`（NSTouchBarDelegate 需要） |
| 標記 | `@MainActor`、`final` |
| 依賴 | `TerminalSession`（`weak` 持有） |

---

### `weak var` — 弱引用，避免循環引用

**問題**：A 強持有 B，B 又強持有 A → 兩個都無法釋放（memory leak）

```
AppDelegate ──強引用──▶ TouchBarController
AppDelegate ──強引用──▶ TerminalSession
TouchBarController ──弱引用──▶ TerminalSession  ✅ 不循環
```

```swift
private weak var session: TerminalSession?
// weak 必須是 var（值可能變 nil）
// weak 必須搭配 Optional（?）
```

**判斷規則**：「誰被誰擁有」，被擁有的那方用 `weak` 參考回擁有者

---

### `super.init()` 呼叫順序

```swift
init(session: TerminalSession) {
    self.session = session   // ① 先設定自己的屬性
    super.init()             // ② 再呼叫父類別 init
    setupViews()             // ③ 最後才能呼叫 self 的方法
    bindSession()
}
```
Swift 強制規定：`super.init()` 前不能呼叫 `self` 的任何方法

---

### `extension` — 職責分離

```swift
final class TouchBarController: NSObject { }        // 主體：屬性 + init

extension TouchBarController: NSTouchBarDelegate { } // Delegate 實作

private extension NSTouchBarItem.Identifier { }      // 自訂 ID
```
每個 extension 只做一件事，大型檔案也容易維護

---

### `// MARK: -` — Xcode 導航標籤

```swift
// MARK: - Setup
// MARK: - NSTouchBarDelegate
```
Xcode breadcrumb 下拉選單會顯示這些標籤，快速跳到對應區塊

---

### `combineLatest` — 多 Publisher 合併

```swift
session.$inputBuffer
    .combineLatest(session.$promptString)
    .sink { buffer, prompt in
        label.stringValue = "\(prompt)\(buffer)_"
    }
```

| 情況 | 行為 |
|---|---|
| `inputBuffer` 改變 | 觸發，帶入新 buffer + 舊 prompt |
| `promptString` 改變 | 觸發，帶入舊 buffer + 新 prompt |

**對比**：`.sink` = 單一 Publisher；`combineLatest` = 任一改變都重算

---

### `private extension` — 擴充 Apple 型別

```swift
private extension NSTouchBarItem.Identifier {
    static let terminalOutput = NSTouchBarItem.Identifier("com.tbt.output")
}

// 使用：
bar.defaultItemIdentifiers = [.terminalOutput]  // 不用寫字串，不會打錯
```

---

### NSStackView 設定速查

```swift
let stack = NSStackView(views: [outputLabel, inputLabel])
stack.orientation  = .vertical       // 垂直排列
stack.spacing      = 2               // 行間距
stack.distribution = .fillEqually    // 兩行等高
stack.alignment    = .leading        // 靠左（預設置中！）
stack.widthAnchor.constraint(equalToConstant: 600).isActive = true
outputItem.view = stack              // 只設定一次
```

**常見陷阱**：
- 忘記 `alignment = .leading` → 文字置中
- `outputItem.view` 設定兩次 → 後者蓋掉前者
- 加 `translatesAutoresizingMaskIntoConstraints = false` → layout 遞迴 warning

---

### 完整資料流圖

```
TerminalSession                    TouchBarController
─────────────────                  ──────────────────
$lastOutputLine ──Combine──▶ outputLabel.stringValue（上排）
$inputBuffer    ──combineLatest──▶
$promptString                  inputLabel.stringValue（下排）
```
