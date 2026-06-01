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
  └── NSCustomTouchBarItem    ← 一個「格子」（item）
        └── NSView            ← 格子裡的內容（任何 NSView 都可以放）
              └── NSStackView ← 我們用來垂直排列兩行文字
                    ├── NSTextField  ← 上排：輸出行
                    └── NSTextField  ← 下排：prompt + 輸入
```

### NSTouchBar — 容器

```swift
let bar = NSTouchBar()

// delegate：誰來「提供」各個 item（當 Touch Bar 需要顯示某個 item 時回呼 delegate）
bar.delegate = self

// defaultItemIdentifiers：要顯示哪些 items，用 Identifier 陣列指定
// 順序 = 在 Touch Bar 上從左到右的順序
bar.defaultItemIdentifiers = [.terminalOutput]
```

### NSCustomTouchBarItem — 格子

```swift
// identifier：這個 item 的唯一識別碼
// 格式建議用 reverse-DNS，例如 "com.tbt.output"，避免和系統 item 衝突
let item = NSCustomTouchBarItem(identifier: .terminalOutput)

// view：格子裡放什麼（任何 NSView 的子類別都可以）
item.view = stackView
```

### NSTouchBarDelegate — 提供 item 的協定

```swift
// extension 讓 TouchBarController 遵守 NSTouchBarDelegate
extension TouchBarController: NSTouchBarDelegate {

    // 當 Touch Bar 需要顯示某個 identifier 的 item 時，系統呼叫這個方法
    // 參數 identifier：要求的 item 識別碼
    // 回傳值：對應的 NSTouchBarItem（或 nil 表示不提供）
    func touchBar(_ touchBar: NSTouchBar,
                  makeItemForIdentifier identifier: NSTouchBarItem.Identifier)
                  -> NSTouchBarItem? {
        switch identifier {
        case .terminalOutput: return outputItem   // 提供我們預先建好的 item
        default: return nil
        }
    }
}
```

**Delegate 模式**：你不直接呼叫 `makeItemForIdentifier`，而是 `NSTouchBar` 在需要時「回呼（callback）」你的 delegate。這是 AppKit 的核心設計模式。

---

## 2. NSStackView — 版面配置詳解

類似 CSS flexbox，把多個 view 排成一排或一列：

```swift
// 初始化：直接傳入要排列的 views 陣列
let stack = NSStackView(views: [outputLabel, inputLabel])

// orientation：排列方向
stack.orientation = .vertical      // 垂直排列（上下）
// stack.orientation = .horizontal // 水平排列（左右）

// spacing：相鄰 view 之間的間距（point 單位）
stack.spacing = 2

// distribution：如何分配空間給各個子 view
stack.distribution = .fillEqually  // 每個 view 等高（vertical）或等寬（horizontal）
// .fill：讓最後一個 view 填滿剩餘空間
// .fillProportionally：依各 view 的 intrinsic size 比例分配

// alignment：子 view 的對齊方式
// orientation = .vertical 時，alignment 控制水平對齊
stack.alignment = .leading         // 靠左對齊（非常重要！預設是 .centerX，即置中）
// .trailing：靠右
// .centerX：置中（預設值，通常不是你要的）

// 固定寬度：Touch Bar 上必須指定，否則 stack 寬度為 0（沒有 intrinsic width）
stack.widthAnchor.constraint(equalToConstant: 600).isActive = true
//               ↑ Auto Layout constraint，600pt ≈ Touch Bar 可用寬度
//               .isActive = true：啟用這個 constraint（不啟用不會生效）
```

### 常見陷阱：設定順序

```swift
// ❌ 錯誤：在 NSStackView 的子 view 上手動設 translatesAutoresizingMaskIntoConstraints
outputItem.view = stack
label.translatesAutoresizingMaskIntoConstraints = false  // 造成 layout 遞迴警告！

// ✅ 正確：NSStackView 自己管理子 view 的 constraints，不要干涉
// 直接把 label 加進 NSStackView，什麼都不用設
```

---

## 3. NSTextField — 文字顯示詳解

```swift
// labelWithString：建立「唯讀標籤」樣式的 NSTextField
// 等同於手動設定：isBordered=false, isEditable=false, drawsBackground=false, isBezeled=false
let label = NSTextField(labelWithString: "初始文字")

// font：字體設定
// NSFont(name:size:) 回傳 Optional<NSFont>（字體可能不存在）
// ?? 提供備用字體：找不到 SFMono 時用系統等寬字體
label.font = NSFont(name: "SFMono-Regular", size: 11)
          ?? NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)

label.textColor = .white           // NSColor，.white 是預設的白色
label.backgroundColor = .clear    // 透明背景（Touch Bar 是黑色，設 clear 就對了）
label.isBordered = false           // 不顯示外框線
label.isEditable = false           // 不可讓使用者輸入
label.alignment = .left            // NSTextAlignment.left，文字靠左

// 更新文字（這個操作必須在主執行緒）
label.stringValue = "最新輸出行"
```

**`NSFont(name:size:)` 為什麼回傳 Optional？**
字體名稱是字串，如果系統沒安裝這個字體就找不到，所以設計成可能回傳 `nil`，需要用 `??` 提供備用方案。

---

## 4. MVVM 架構

本專案採用 **MVVM（Model-View-ViewModel）** 架構：

```
Model          ViewModel           View
PTYBridge  →  TerminalSession  →  TouchBarController
（Shell）      （狀態管理）         （Touch Bar UI）
```

- **Model**：PTYBridge，管理真實的 shell 行程，只負責 I/O
- **ViewModel**：TerminalSession，持有 UI 需要的狀態（`@Published`），處理資料轉換
- **View**：TouchBarController，訂閱 ViewModel 的狀態變化並更新 UI，不包含業務邏輯

**好處**：View 和 Model 完全解耦，測試 TerminalSession 不需要 Touch Bar，替換 UI 也不影響 PTY 邏輯。

---

## 5. Combine — 響應式資料綁定

Combine 是 Apple 的響應式框架，核心概念：**值改變時，自動通知訂閱者**。

類比：Python 的 `event / callback`，但更系統化、有型別安全。

### `@Published` — 可觀察的屬性

```swift
// ObservableObject：讓這個 class 可以被 Combine 觀察
class TerminalSession: ObservableObject {

    // @Published：這個屬性值改變時，自動發出通知給所有訂閱者
    // 背後機制：每次 lastOutputLine = x 時，呼叫所有 subscriber 的 closure
    @Published var lastOutputLine: String = ""
    @Published var inputBuffer: String = ""
    @Published var promptString: String = "% "
}
```

**`@Published` 背後的機制**：
- `@Published var foo: String` 自動產生一個 Publisher，名稱是 `$foo`
- 型別：`Published<String>.Publisher`（等同 `Publisher<String, Never>`）
- 每次 `foo` 被賦值，`$foo` 就發出（emit）新的值給所有訂閱者
- `Never` 代表這個 publisher 永遠不會發出錯誤

### `sink` — 訂閱並處理值

```swift
// $ 前綴：取得 @Published 屬性對應的 Publisher
session.$lastOutputLine

    // receive(on:)：指定後續 operator 和 sink 在哪個 queue（執行緒）執行
    // DispatchQueue.main = 主執行緒（更新 AppKit UI 必須在主執行緒）
    .receive(on: DispatchQueue.main)

    // sink：最終訂閱點，每次有新值就執行 receiveValue closure
    // [weak self]：弱引用，避免循環引用（見第 7 節）
    .sink { [weak self] newValue in
        self?.outputLabel.stringValue = newValue
    }

    // store(in:)：把訂閱的 AnyCancellable token 存進 Set
    // &cancellables：inout 參數，讓 store 可以修改 cancellables
    .store(in: &cancellables)
```

**為什麼需要 `receive(on: DispatchQueue.main)`？**

`@Published` 的值可能在任何執行緒被修改（例如 Phase 2 的 PTY bridge 在 background thread 更新值），`receive(on:)` 確保 sink closure 一定在主執行緒執行，安全更新 UI。

### `combineLatest` — 合併多個 Publisher

```swift
// 問題：inputLabel 需要同時顯示 prompt 和 input，但它們是兩個 @Published 屬性
// 解法：combineLatest 任一 publisher 有新值就合併兩者最新值，通知一次

session.$inputBuffer
    .combineLatest(session.$promptString)
    // 收到的是 tuple：(inputBuffer 的新值, promptString 的最新值)
    .receive(on: DispatchQueue.main)
    .sink { [weak self] buffer, prompt in
        // \() 是 Swift 的字串插值，等同 Python 的 f"..."
        self?.inputLabel.stringValue = "\(prompt)\(buffer)_"
        //                             ─────────────────────
        //                             例："% ls -la_"（_ 是游標）
    }
    .store(in: &cancellables)
```

| 情況 | 行為 |
|------|------|
| `inputBuffer` 改變 | 觸發，帶入新 buffer + 舊 prompt |
| `promptString` 改變 | 觸發，帶入舊 buffer + 新 prompt |
| 兩個同時改變 | 觸發兩次（各一次） |

**對比**：`.sink` = 只監聽一個 Publisher；`combineLatest` = 任一改變都重新計算。

---

## 6. `Set<AnyCancellable>` — Combine 訂閱管理

```swift
// 宣告：private，跟著 controller 的生命週期
private var cancellables = Set<AnyCancellable>()
//          ↑ Set：同一個 token 不會重複加入（自動去重）
//  AnyCancellable：type-erased，不管是哪種 publisher 的訂閱，都存成同一型別
```

**為什麼要 `store`？**

```swift
// ❌ 沒有 store：token 在這行結束後立刻被 ARC 釋放，訂閱取消
session.$lastOutputLine.sink { print($0) }

// ✅ 有 store：token 存在 cancellables，跟著物件的生命週期
// 當 controller 被釋放，cancellables 也被釋放，訂閱自動取消（不需要手動 cancel）
session.$lastOutputLine
    .sink { print($0) }
    .store(in: &cancellables)
```

Python 類比：像 `addEventListener`，但你需要保留 handle 才能維持監聽狀態；物件釋放時自動 `removeEventListener`。

---

## 7. `[weak self]` — 避免循環引用

### 什麼情況會循環引用？

```
AppDelegate ──強引用──▶ TouchBarController
AppDelegate ──強引用──▶ TerminalSession
                              │
                              │（Combine publisher 持有 sink closure）
                              ▼
                         sink closure ──強引用──▶ TouchBarController（self）
```

如果 sink closure 強持有 `self`（TouchBarController），就形成循環：
- `TerminalSession` 的 publisher → closure → `TouchBarController`
- `TouchBarController` 的 `cancellables` → AnyCancellable → publisher
- 兩者互相持有，ARC 無法釋放

### 解法：`[weak self]`

```swift
// ❌ 危險：closure 強持有 self，可能造成 retain cycle
.sink { self.outputLabel.stringValue = newValue }

// ✅ 安全：[weak self] 讓 closure 弱持有 self
.sink { [weak self] newValue in
    // self? 是 Optional：如果 self 已被釋放，self? 是 nil
    self?.outputLabel.stringValue = newValue
    // ?. 是 Optional chaining：self? 為 nil 時整行跳過，不 crash
}
```

**判斷是否需要 `[weak self]`**：
- Escaping closure（Combine sink、`DispatchQueue.async`）且 closure 和 self 互相持有 → **需要**
- Non-escaping closure（`map`、`filter`、`forEach`）→ **不需要**，不會造成 cycle

---

## 8. `weak var` — 弱引用屬性

```swift
// TouchBarController 持有 session 的參考，但不想「擁有」它
// AppDelegate 才是擁有者
private weak var session: TerminalSession?
```

**三條規則**：
1. `weak` 必須是 `var`（值可能隨時被 ARC 設成 nil）
2. `weak` 必須搭配 Optional（`?`），因為值可能是 nil
3. 被參考的物件釋放後，`weak var` 自動變成 `nil`（不會 dangling pointer crash）

**所有權圖**：

```
AppDelegate ──強引用──▶ TouchBarController   AppDelegate「擁有」TC
AppDelegate ──強引用──▶ TerminalSession      AppDelegate「擁有」Session
TouchBarController ──弱引用──▶ TerminalSession  TC「認識」Session，但不擁有
```

`AppDelegate` 釋放 → `TouchBarController` 和 `TerminalSession` 各自釋放 → TC 的 `weak session` 自動變 nil。

---

## 9. `super.init()` 呼叫順序

```swift
init(session: TerminalSession) {
    // Phase 1：先設定自己的所有 stored property（Swift 強制規定）
    self.session = session

    // Phase 2：呼叫父類別 init
    // NSObject 的 init 做 ObjC runtime 的初始化（KVO、selector 等）
    super.init()

    // Phase 3：super.init() 之後才能呼叫 self 的方法
    setupViews()     // ❌ 在 super.init() 前呼叫 → 編譯錯誤
    bindSession()
}
```

Swift 的 two-phase initialization 規則：Phase 1 確保所有屬性有初始值 → Phase 2 才能使用 self。

---

## 10. `extension` — 職責分離

```swift
// 主體：只放屬性宣告和 init
final class TouchBarController: NSObject {
    private weak var session: TerminalSession?
    private var cancellables = Set<AnyCancellable>()
    private let outputItem: NSCustomTouchBarItem
    // ...
    init(session: TerminalSession) { ... }
}

// extension 1：UI 建立邏輯（分離讓主體更簡潔）
extension TouchBarController {
    // MARK: - Setup
    private func setupViews() { ... }
    private func bindSession() { ... }
}

// extension 2：遵守 NSTouchBarDelegate 協定
// 把 delegate 實作獨立出來，一眼就知道這個 class 遵守什麼協定
extension TouchBarController: NSTouchBarDelegate {
    func touchBar(...) -> NSTouchBarItem? { ... }
}

// extension 3：擴充 Apple 型別，加入自訂常數
// private：只有這個檔案能用
private extension NSTouchBarItem.Identifier {
    // static let：類別層級的常數（用 .terminalOutput 存取，不需要 instance）
    static let terminalOutput = NSTouchBarItem.Identifier("com.tbt.output")
}
// 使用：bar.defaultItemIdentifiers = [.terminalOutput]（不用硬寫字串）
```

---

## 11. `// MARK: -` — Xcode 導航標籤

```swift
// MARK: - Properties     ← 屬性區塊
// MARK: - Lifecycle      ← init / deinit
// MARK: - Setup          ← setupViews 等
// MARK: - NSTouchBarDelegate  ← Delegate 實作
```

Xcode 的 breadcrumb（editor 上方的路徑列）點開下拉選單會顯示這些標籤，點選可快速跳轉。`-` 讓標籤前顯示一條分隔線。

---

## 12. `NSStatusItem` — Menu Bar 圖示詳解

```swift
// NSStatusBar.system：整個 system 的 status bar（singleton）
// statusItem(withLength:)：在 status bar 新增一個項目
// NSStatusItem.squareLength：item 寬度等於高度（正方形），適合圖示或單字元
let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

// button：status bar 上的按鈕（Optional，理論上不應該是 nil）
statusItem.button?.title = "⌨"
// 也可以放 SF Symbol 圖示：
// statusItem.button?.image = NSImage(systemSymbolName: "terminal", accessibilityDescription: nil)

// ── 建立下拉選單 ──
let menu = NSMenu()

// NSMenuItem(title:action:keyEquivalent:)：一個選單項目
// action：點選時呼叫的方法（#selector 形式），nil 表示純文字標題
// keyEquivalent：快捷鍵字母，"" 表示無快捷鍵，"q" = Cmd+Q
menu.addItem(NSMenuItem(title: "TouchBarTerminal", action: nil, keyEquivalent: ""))
menu.addItem(.separator())  // NSMenuItem.separator()：水平分隔線
menu.addItem(NSMenuItem(
    title: "Quit",
    action: #selector(NSApplication.terminate(_:)),
    keyEquivalent: "q"
))

// 把選單掛到 status item
statusItem.menu = menu
```

### `#selector` 是什麼？

```swift
// #selector 建立一個「方法參考」（Objective-C selector）
// AppKit 在適當時機呼叫這個方法
#selector(NSApplication.terminate(_:))
// 等同 ObjC 的 @selector(terminate:)

// 自訂方法要加 @objc 才能用 #selector：
@objc func handleQuit() { NSApp.terminate(nil) }
menu.addItem(NSMenuItem(title: "Quit", action: #selector(handleQuit), keyEquivalent: "q"))
// 注意：target 預設是 nil，AppKit 會沿著 responder chain 找誰能處理這個 selector
```

---

## 13. Touch Bar 顯示條件

`NSTouchBar` 只在以下條件**同時**成立時顯示：
1. **App 是 frontmost**（最前景應用程式）
2. **System Settings → Keyboard → Touch Bar shows = App Controls**
3. **`NSApp.touchBar` 有被設定**（或 key window 的 `touchBar` 有值）

**LSUIElement App 取得焦點的方式：**
```swift
// 讓 App 變成前景（frontmost），Touch Bar 才會顯示
NSApp.activate(ignoringOtherApps: true)

// 完成後把焦點還給前一個 App（可選，讓使用者繼續在別的 App 打字）
NSApp.hide(nil)
```

---

## 14. 依賴注入（Dependency Injection）

```swift
// ❌ 自己建立（緊耦合）
init() {
    let session = TerminalSession()  // 死綁在一起，測試時無法替換
}

// ✅ 由外部傳入（鬆耦合）
init(session: TerminalSession) {
    self.session = session   // 測試時傳入 MockTerminalSession
}
```

**AppDelegate 負責組裝**：

```swift
func applicationDidFinishLaunching(_ notification: Notification) {
    let session = TerminalSession()                          // 建立一個實例
    let tbController = TouchBarController(session: session)  // 注入同一個 session
    let statusController = StatusItemController(session: session)  // 同一個 session
    // 所有 controller 共用同一個 session，狀態一致
}
```

---

## 15. `final class` vs `class`

| | 說明 |
|---|---|
| `class` | 可以被繼承（subclass） |
| `final class` | **不能**被繼承，編譯器可做靜態 dispatch 最佳化 |

ViewModel 和 Controller 通常都標 `final`：我們確定不會繼承它，同時獲得一點效能提升。

---

## 16. XcodeGen 工作流程

每次新增或刪除 Swift 檔案，都要：
```bash
xcodegen generate
```
然後在 Xcode 選 **Load Changes**。

**注意**：空資料夾不會出現在 Xcode，資料夾裡至少要有一個檔案。

---

## 17. 完整資料流圖

```
TerminalSession                    TouchBarController
─────────────────                  ──────────────────
@Published $lastOutputLine ──sink──▶ outputLabel.stringValue（上排）

@Published $inputBuffer    ──combineLatest──▶ inputLabel.stringValue（下排）
@Published $promptString   ──────────────────▶ 格式："\(prompt)\(buffer)_"

                                   StatusItemController
                                   ─────────────────────
@Published $isConnected    ──sink──▶ statusItem.button?.title
                                     連線中："⌨"  斷線："⌨?"
```

---

## 18. 驗收標準

- [x] Touch Bar 顯示兩行文字（上排輸出、下排 prompt）
- [x] 文字靠左對齊
- [x] 使用等寬字體（SF Mono）
- [x] Menu bar 有 `⌨` 圖示
- [x] 點圖示後 Touch Bar 出現內容

---

## 19. 實作順序與每個檔案的職責

### 建立順序
```
1. main.swift               → App 入口點
2. AppDelegate.swift        → App 生命週期管理，組裝所有元件
3. TerminalSession.swift    → ViewModel（狀態中心，@Published 屬性）
4. StatusItemController.swift → Menu Bar 圖示，訂閱 isConnected
5. TouchBarController.swift → Touch Bar UI，訂閱 lastOutputLine 等
```

### 為什麼這個順序？
- `TerminalSession` 是核心，其他人都依賴它，先建立
- `StatusItemController` 和 `TouchBarController` 都需要 `TerminalSession` 才能初始化
- 最後才在 `AppDelegate` 把所有東西組裝起來（依賴注入）
