# TouchBarTerminal 開發 Spec — Phase 0 to Phase 2

> 這份文件是給自己回顧用的完整技術說明。
> 每個概念都對應到實際的程式碼，讀完應該能清楚說出「為什麼這樣寫」。

---

## 目錄

1. [專案定位](#1-專案定位)
2. [技術選型決策](#2-技術選型決策)
3. [App 啟動流程](#3-app-啟動流程)
4. [MVVM 架構](#4-mvvm-架構)
5. [Swift 核心概念](#5-swift-核心概念)
6. [Touch Bar UI 層](#6-touch-bar-ui-層)
7. [PTY 底層通訊](#7-pty-底層通訊)
8. [Combine 資料綁定](#8-combine-資料綁定)
9. [常見陷阱速查](#9-常見陷阱速查)
10. [檔案職責總表](#10-檔案職責總表)

---

## 1. 專案定位

**TouchBarTerminal** 是一個 macOS menu bar App，把 Touch Bar 變成持久存活的 zsh 迷你終端機。

### 核心行為
- 按 `⌃⌥Space` → App 取得焦點 → Touch Bar 變成終端機
- 鍵盤輸入直接打進 PTY → zsh 執行 → 輸出顯示在 Touch Bar 上排
- 再按 `⌃⌥Space` → 焦點還給前一個 App → PTY session **不死**

### 目標機型
- MacBook Pro M2 13"（2022，最後一台有 Touch Bar 的 Mac）
- 同時相容 Intel Touch Bar MBP（2016–2020）

---

## 2. 技術選型決策

| 決策 | 選擇 | 原因 |
|---|---|---|
| 顯示策略 | App 聚焦時顯示（A1） | 純公開 API，不會被 macOS 更新打壞 |
| 輸入方式 | 點 Touch Bar 後接管鍵盤 | 不需要 Accessibility 權限 |
| Shell | 單一持續 zsh session | 保留 cd/export 等狀態 |
| 輸出渲染 | 最後一行純文字 | MVP 範圍，後續可升級 |
| 專案管理 | XcodeGen + project.yml | 純文字設定，避免 git merge conflict |
| 架構模式 | MVVM | UI 與邏輯分離，Combine 驅動更新 |

---

## 3. App 啟動流程

### 入口點：`main.swift`

```swift
import AppKit

MainActor.assumeIsolated {
    let delegate = AppDelegate()
    NSApplication.shared.delegate = delegate
    _ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
}
```

**為什麼不用 `@main`？**
`@main` + `@MainActor` 會有初始化時序衝突。`main.swift` 這個特殊檔名是 Swift 的傳統 entry point，更明確可控。

**`MainActor.assumeIsolated`**：告訴 Swift「這段程式碼在主執行緒上跑」，讓我們可以建立 `@MainActor` 標記的物件。

### `AppDelegate` 的職責

```swift
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var session: TerminalSession?
    private var touchBarController: TouchBarController?
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)  // 不顯示 Dock 圖示

        let session = TerminalSession()
        self.session = session                 // 強引用，防止被 ARC 釋放

        let tbController = TouchBarController(session: session)
        self.touchBarController = tbController

        self.statusItemController = StatusItemController(session: session)

        NSApp.touchBar = tbController.makeTouchBar()  // 掛到 App 層級

        session.start()  // fork PTY
    }
}
```

**關鍵**：三個物件都存到 `self`（強引用），否則 `applicationDidFinishLaunching` 結束後 ARC 會釋放它們。

### LSUIElement — 純 Menu Bar App

```xml
<!-- Info.plist -->
<key>LSUIElement</key>
<true/>
```

效果：
- Dock 不顯示圖示
- App 切換（Cmd+Tab）不出現
- 只能透過 menu bar 圖示或程式碼 `NSApp.activate()` 取得焦點

---

## 4. MVVM 架構

```
[ View 層 ]                    [ ViewModel 層 ]       [ Model 層 ]
TouchBarController    ←─────── TerminalSession ──────▶ PTYBridge
StatusItemController  ←─────── （@Published）          AnsiStripper
                                                       CommandHistory
```

### 各層職責

| 層 | 類別 | 職責 |
|---|---|---|
| View | `TouchBarController` | 渲染 Touch Bar，訂閱 ViewModel 更新 UI |
| View | `StatusItemController` | 渲染 menu bar 圖示 |
| ViewModel | `TerminalSession` | 持有所有狀態，協調 PTY 與 UI |
| Model | `PTYBridge` | 管理 zsh 子行程，I/O 通訊 |
| Utility | `AnsiStripper` | 剝除 ANSI escape codes |
| Utility | `CommandHistory` | 環狀歷史緩衝 |

### 資料流向（單向）

```
PTYBridge.drain()
    │ onOutput callback
    ▼
TerminalSession.lastOutputLine = line   (@Published)
    │ Combine Publisher
    ▼
TouchBarController.outputLabel.stringValue
```

---

## 5. Swift 核心概念

### 5.1 `let` vs `var`

```swift
let name = "hello"   // 不可變，建立後不能改
var count = 0        // 可變
```

### 5.2 Optional（?）

```swift
var title: String? = nil   // 可能是 nil
title = "hello"

// 使用前解包
if let t = title { print(t) }
let display = title ?? "預設值"   // nil 時用預設值
self?.doSomething()               // self 是 nil 時不執行
```

### 5.3 `@MainActor`

UI 操作必須在主執行緒。`@MainActor` 標記讓 Swift 自動確保這一點：

```swift
@MainActor
final class TerminalSession: ObservableObject {
    // 所有方法都在主執行緒執行
}
```

**錯誤訊息**：
```
Main actor-isolated property 'xxx' can not be referenced from a nonisolated context
```
**解法**：在 class 宣告前加 `@MainActor`

### 5.4 `final class` vs `struct`

| | `class` | `final class` | `struct` |
|---|---|---|---|
| 繼承 | ✅ | ❌ | ❌ |
| 傳遞方式 | 參考（共享） | 參考（共享） | 值（複製） |
| `mutating` | 不需要 | 不需要 | 需要 |
| 適合 | 有繼承需求 | Controller/ViewModel | 純資料容器 |

### 5.5 `weak` 弱引用

避免循環引用（memory leak）：

```swift
// AppDelegate 強持有 TouchBarController
// TouchBarController 弱持有 TerminalSession（AppDelegate 也強持有）
private weak var session: TerminalSession?
```

**判斷規則**：「誰被誰擁有」，被擁有的那方用 `weak` 參考回擁有者

### 5.6 `extension` — 職責分離

```swift
// 主 class：屬性 + init
final class TouchBarController: NSObject { }

// Delegate 實作獨立放
extension TouchBarController: NSTouchBarDelegate {
    func touchBar(...) -> NSTouchBarItem? { }
}

// 自訂型別擴充
private extension NSTouchBarItem.Identifier {
    static let terminalOutput = NSTouchBarItem.Identifier("com.tbt.output")
}
```

### 5.7 `// MARK: -`

```swift
// MARK: - Setup
// MARK: - NSTouchBarDelegate
```

在 Xcode breadcrumb 下拉選單顯示分段標籤，快速跳轉。

---

## 6. Touch Bar UI 層

### 6.1 NSTouchBar 三層結構

```
NSTouchBar                          ← 整條 Touch Bar
  └── NSCustomTouchBarItem          ← 一個格子
        └── NSStackView             ← 垂直排列容器
              ├── NSTextField       ← 上排：輸出
              └── NSTextField       ← 下排：prompt + 輸入
```

### 6.2 建立 Touch Bar

```swift
func makeTouchBar() -> NSTouchBar {
    let bar = NSTouchBar()
    bar.delegate = self
    bar.defaultItemIdentifiers = [.terminalOutput]
    return bar
}

// Delegate：系統詢問「給我這個 identifier 的 item」
func touchBar(_ touchBar: NSTouchBar,
              makeItemForIdentifier identifier: NSTouchBarItem.Identifier)
              -> NSTouchBarItem? {
    switch identifier {
    case .terminalOutput: return outputItem
    default: return nil
    }
}
```

### 6.3 NSStackView 設定

```swift
let stack = NSStackView(views: [outputLabel, inputLabel])
stack.orientation  = .vertical       // 垂直排列
stack.spacing      = 2               // 行間距
stack.distribution = .fillEqually    // 兩行等高
stack.alignment    = .leading        // 靠左（預設是置中！）
stack.widthAnchor.constraint(equalToConstant: 600).isActive = true
outputItem.view = stack              // 只設定一次
```

**常見陷阱**：
- 忘記 `alignment = .leading` → 文字置中
- `outputItem.view` 設定兩次 → 後者蓋掉前者
- 加 `translatesAutoresizingMaskIntoConstraints = false` → layout 遞迴 warning

### 6.4 NSTextField 設定

```swift
let label = NSTextField(labelWithString: "")
label.font = NSFont(name: "SFMono-Regular", size: 11)
         ?? NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
label.textColor      = .white
label.backgroundColor = .clear
label.isBordered     = false
label.isEditable     = false
label.alignment      = .left
label.stringValue    = "更新文字"   // 更新顯示
```

### 6.5 Touch Bar 顯示條件

全部要同時成立：
1. App 是 frontmost（最前景）
2. System Settings → Keyboard → Touch Bar shows = **App Controls**
3. `NSApp.touchBar` 有設定

---

## 7. PTY 底層通訊

### 7.1 什麼是 PTY

```
你的 App ←→ PTY master fd ←→ PTY slave fd ←→ zsh
              （讀寫指令）                    （以為自己在真實終端）
```

為什麼不用 subprocess：
- `cd`、`export` 狀態不持久
- shell 偵測到不是終端機，不顯示 prompt

### 7.2 forkpty() 流程

```swift
var master: Int32 = 0
var windowSize = winsize(ws_row: 1, ws_col: 200, ws_xpixel: 0, ws_ypixel: 0)
let pid = forkpty(&master, nil, nil, &windowSize)

if pid == 0 {
    // === 子行程 ===
    setenv("TERM", "dumb", 1)
    var args: [UnsafeMutablePointer<CChar>?] = [strdup(shell), strdup("-l"), nil]
    execv(shell, &args)   // 替換成 zsh（execl 在 Swift 不可用）
    exit(1)
}

// === 父行程 ===
self.masterFD = master   // 用這個 fd 讀寫
self.childPID = pid
```

| pid 值 | 意思 |
|---|---|
| `< 0` | fork 失敗 |
| `== 0` | 現在是子行程 |
| `> 0` | 現在是父行程，值是子行程 PID |

### 7.3 非同步讀取（DispatchSource）

```swift
let source = DispatchSource.makeReadSource(
    fileDescriptor: masterFD,
    queue: .global(qos: .userInitiated)
)
source.setEventHandler { [weak self] in
    self?.drain()   // 有資料可讀才觸發，不 polling
}
source.setCancelHandler { Darwin.close(masterFD) }
source.resume()
```

### 7.4 執行緒安全

```
讀取（drain）   → .global 背景 queue
寫入（write）   → 獨立序列 writeQueue
UI 更新         → DispatchQueue.main（@MainActor）
```

### 7.5 ANSI Escape 剝除

zsh 輸出夾雜控制碼：
```
\x1B[1;34m/Users/smallfire\x1B[0m %
```

剝除後：
```
/Users/smallfire %
```

Regex：
```swift
let pattern = #"\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])"#
```

---

## 8. Combine 資料綁定

### 8.1 @Published + ObservableObject

```swift
@MainActor
final class TerminalSession: ObservableObject {
    @Published var lastOutputLine: String = ""  // 改變時自動通知
}
```

### 8.2 訂閱（sink）

```swift
session.$lastOutputLine              // $ 前綴取得 Publisher
    .receive(on: DispatchQueue.main) // 確保主執行緒
    .sink { [weak self] line in      // 每次值改變觸發
        self?.outputLabel.stringValue = line
    }
    .store(in: &cancellables)        // 存起來，否則立刻釋放
```

### 8.3 combineLatest

```swift
session.$inputBuffer
    .combineLatest(session.$promptString)
    .sink { buffer, prompt in
        label.stringValue = "\(prompt)\(buffer)_"
    }
```

任一個改變都觸發，帶入兩者最新值。

### 8.4 Set\<AnyCancellable\>

```swift
private var cancellables = Set<AnyCancellable>()
// .store(in: &cancellables) 把訂閱存進來
// class 釋放時，cancellables 釋放，訂閱自動取消
```

---

## 9. 常見陷阱速查

| 陷阱 | 症狀 | 解法 |
|---|---|---|
| `@main` + `@MainActor` 衝突 | App 啟動無反應 | 改用 `main.swift` |
| 強引用循環 | 記憶體洩漏 | 用 `weak` 打破循環 |
| Touch Bar 空白 | 沒有輸出 | App 不是 frontmost，點 menu bar 圖示 |
| 文字置中 | `% _` 在 Touch Bar 中間 | 加 `stack.alignment = .leading` |
| layout 遞迴 warning | Console 報錯 | 移除 `translatesAutoresizingMaskIntoConstraints` |
| `Main actor-isolated` 錯誤 | Build 失敗 | 在 class 加 `@MainActor` |
| `execl` 不可用 | Build 失敗 | 改用 `execv` + `strdup` |
| 訂閱立刻消失 | UI 不更新 | `.store(in: &cancellables)` |
| 物件被 ARC 釋放 | App 無反應 | 存到 `self` 的 property |

---

## 10. 檔案職責總表

| 檔案 | 層 | 職責 |
|---|---|---|
| `main.swift` | Entry | App 入口點 |
| `AppDelegate.swift` | App | 建立所有物件，設定 Touch Bar |
| `Info.plist` | Config | `LSUIElement=YES`，最低 macOS |
| `TerminalSession.swift` | ViewModel | 狀態中心，協調 PTY 與 UI |
| `CommandHistory.swift` | Utility | 環狀歷史緩衝（struct，容量 100） |
| `AnsiStripper.swift` | Utility | 剝除 ANSI codes，取最後一行 |
| `PTYBridge.swift` | Model | forkpty、DispatchSource 讀寫 |
| `TouchBarController.swift` | View | NSTouchBar UI，Combine 訂閱 |
| `StatusItemController.swift` | View | NSStatusItem menu bar 圖示 |
| `KeyboardInterceptor.swift` | Input | NSEvent 攔截（Phase 3） |
| `GlobalHotKey.swift` | Input | Carbon 全域熱鍵（Phase 5） |

---

*最後更新：Phase 2 完成*

---

# Phase 5 補充：全域熱鍵

## 為什麼不能用 NSEvent
`NSEvent.addLocalMonitorForEvents` 只在自己 App 為前景時收得到。全域熱鍵需要在「別的 App 也能觸發」，所以用 Carbon `RegisterEventHotKey`（不需 Accessibility 權限）。

## Carbon 全域熱鍵流程
```
RegisterEventHotKey(keyCode, modifiers)  → 註冊
        ↓
系統偵測 ⌃⌥Space
        ↓
InstallEventHandler 的 C callback 被呼叫
        ↓
DispatchQueue.main.async → toggleFocus()
```

## 關鍵技術點

### 靜態字典存 callback
Carbon callback 是舊式 C 函式指標，**不能捕捉 Swift 的 self**。用靜態字典 `[hotkeyID: callback]` 對應，callback 裡查字典執行。

### @escaping
```swift
init(action: @escaping () -> Void)
```
closure 會存到字典晚點才執行，「逃出」init 生命週期，必須標 @escaping。

### modifiers bitmask
```swift
let ctrlOpt = UInt32(controlKey | optionKey)  // OR 合併兩個修飾鍵 bit
```

### keyCode
Space = 49。

## 焦點切換
```swift
private func toggleFocus() {
    if NSApp.isActive {
        NSApp.hide(nil)                        // 還焦點給上一個 App
    } else {
        NSApp.activate(ignoringOtherApps: true)  // 取得焦點，Touch Bar 變終端
    }
}
```

LSUIElement + accessory policy → activate 時不跳視窗、不搶 Dock 動畫。

## 指令 echo 過濾（多段問題）
zsh 會把輸入指令 echo 回來，且長指令可能被換行切成多段（`cd De` + `sktop`）。
解法：送出時記下 `pendingEchoSkip`（去空白的指令），每段輸出從前綴逐步扣掉：

```swift
private func shouldSkipAsEcho(_ line: String) -> Bool {
    guard !pendingEchoSkip.isEmpty else { return false }
    let stripped = line.replacingOccurrences(of: " ", with: "")
    if pendingEchoSkip.hasPrefix(stripped) {
        pendingEchoSkip.removeFirst(stripped.count)
        return true
    }
    return false
}
```

## 驗收
- [x] 在任何 App 按 ⌃⌥Space → Touch Bar 變終端
- [x] 再按一次 → 焦點還給原 App，session 不死
- [x] 右側不再顯示指令 echo

---

# Phase 4 補充：指令歷史、Ctrl+C、Tab

## 功能對應

| 功能 | 按鍵 | 實作位置 |
|---|---|---|
| 指令歷史 | ↑ / ↓ | `historyPrevious()` / `historyNext()` + `CommandHistory` 環狀緩衝 |
| 中斷指令 | ⌃C | `sendControlChar(0x03)` 送 SIGINT |
| 自動補全 | Tab | `sendControlChar(0x09)` 透傳給 zsh，由 zsh 自己補全 |

## TERM 環境變數的關鍵抉擇

| TERM 值 | 補全 | 輸出乾淨度 |
|---|---|---|
| `dumb` | ❌ 不支援 | 最乾淨 |
| `xterm` | ✅ 支援 | 可接受（我們的 ANSI 剝除能處理） |
| `xterm-256color` | ✅ 支援 | 控制碼最多，風險高 |

**結論**：用 `xterm`——補全可用，輸出也不會亂掉。

```swift
setenv("TERM", "xterm", 1)  // 不是 dumb，才有 Tab 補全
```

## Tab 補全為什麼「透傳」就好

我們不自己實作補全邏輯，只把 `Tab`（0x09）原封不動送進 PTY，讓 zsh 自己處理補全並把結果 echo 回來。這是 PTY 架構的優勢：複雜邏輯交給真正的 shell。

## XCTest 單元測試

```swift
import XCTest
@testable import TouchBarTerminal   // 存取內部型別

final class CommandHistoryTests: XCTestCase {
    func test_previous_returns_last_command() {
        var history = CommandHistory()   // Arrange
        history.push("ls")
        history.push("pwd")
        XCTAssertEqual(history.previous(), "pwd")  // Act + Assert
        XCTAssertEqual(history.previous(), "ls")
    }
}
```

- 測試函式名必須 `test` 開頭
- `@testable import` 才能測內部（非 public）型別
- 跑測試：⌘U

### 測試 target 的 Info.plist 問題
測試 target 缺 Info.plist 會 code sign 失敗，在 project.yml 加：
```yaml
GENERATE_INFOPLIST_FILE: YES
CODE_SIGNING_ALLOWED: NO
```

## 驗收
- [x] ↑↓ 叫出指令歷史
- [x] ⌃C 中斷 sleep
- [x] Tab 補全路徑（cd Desk → cd Desktop）
- [x] 單元測試綠燈

---

# Phase 6 補充：即時模式重構（passthrough + TerminalParser）

## 為什麼重構

buffer 模式（自己存 inputBuffer，Enter 才送）無法支援 Tab 補全——因為打字時 zsh 不知道你輸入什麼。改成**即時模式**：每個字立刻送進 zsh，由 zsh 負責 echo/補全/歷史。

但即時模式讓 `TerminalSession.consume` 變成大雜燴（ANSI、行緩衝、prompt 偵測、echo 過濾、顯示格式化全混在一起），改一個壞一個。於是抽出 `TerminalParser`。

## 重構後職責劃分（單一職責原則）

| 檔案 | 職責 | 可測試 |
|---|---|---|
| `PTYBridge` | PTY I/O（讀寫 bytes） | — |
| `TerminalParser` | 解析 raw 字串 → ParserEvent | ✅ 純邏輯 |
| `TerminalSession` | 狀態管理 + 轉發 | — |
| `TouchBarController` | 顯示 | — |

## ParserEvent（結構化事件）

```swift
enum ParserEvent: Equatable {
    case prompt(path: String)       // prompt 行 → 解析路徑
    case output(line: String)       // 指令輸出
    case currentInput(text: String) // 正在輸入的內容
}
```

解析器吐事件，Session 套事件，兩者解耦。

## 關鍵 bug：Swift 把 \r\n 當成單一 Character

```swift
for char in "foo\r\nbar" {
    // char 會是 "f","o","o","\r\n"(整個!),"b","a","r"
    // switch char { case "\n": } 永遠匹配不到！
}
```

Swift 的 String 以 **grapheme cluster** 迭代，`\r\n` 是單一群集。
這就是 pwd 輸出黏在一起的真正原因。

**解法**：feed 開頭先正規化
```swift
let normalized = AnsiStripper.strip(raw)
    .replacingOccurrences(of: "\r\n", with: "\n")
    .replacingOccurrences(of: "\r", with: "\n")
```

## 即時模式按鍵對應（KeyboardInterceptor）

| 按鍵 | 送出 bytes | 說明 |
|---|---|---|
| 一般字元 | UTF-8 | 立即 echo |
| Enter | `0x0d` (\r) | zsh 認回車 |
| Backspace | `0x7f` (DEL) | |
| Tab | `0x09` | zsh 自己補全 |
| ↑ | `ESC [ A` (0x1b 0x5b 0x41) | zsh 歷史 |
| ↓ | `ESC [ B` | |
| ← → | `ESC [ D` / `ESC [ C` | 游標移動 |
| ⌃C 等 | `scalar - 0x60` | a→1, c→3, l→12 |

## 測試驅動：把每個 bug 變成測試

8 個測試鎖死所有踩過的雷：
- prompt 與指令黏一起（"%pwd"）
- user@host 回顯行
- \r\n 分行
- ANSI 剝除
- backspace echo

改了程式跑 `xcodebuild test`，不用每次手動 ⌘R。

## CLI 跑測試
```bash
xcodebuild test -project TouchBarTerminal.xcodeproj \
  -scheme TouchBarTerminal -destination 'platform=macOS' \
  -only-testing:TouchBarTerminalTests/TerminalParserTests
```
