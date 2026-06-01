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

---

## 3. Swift vs Python 基礎對照

```swift
// 變數
let name = "hello"   // let = 不可變（唯讀）
var count = 42       // var = 可變

// 類別
class AppDelegate: NSObject {
    var session: TerminalSession?   // ? = 可能是 nil（Optional）
    
    init() {
        super.init()   // 必須呼叫父類別 init
    }
}

// 函式
func applicationDidFinishLaunching(_ notification: Notification) {
    print("App launched")
}
```

```python
# Python 對照
name = "hello"       # 沒有 let/var 區分
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
var title: String? = nil   // ? 表示「可能是 nil」
title = "hello"

// 使用前必須解包
if let t = title {
    print(t)           // 確定有值才進來
}

let display = title ?? "no title"   // ?? 給預設值
```

**為什麼這樣設計？** 強迫開發者處理「沒有值」的情況，避免 NullPointerException。

---

## 5. `@MainActor` — Swift 並發基礎

macOS UI **必須**在主執行緒（Main Thread）上操作。Swift 用 `@MainActor` 來保證這一點。

```swift
@MainActor
class TouchBarController {
    // 這個 class 的所有操作都在主執行緒
}
```

**規則**：只要一個 class 用到 `@MainActor` 的東西，它自己也要標 `@MainActor`。

錯誤訊息長這樣：
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
```

### 方式 B：`main.swift`（我們用這個）
```swift
// main.swift — 檔名一定要叫 main，這是 Swift 的特殊規則
import AppKit

MainActor.assumeIsolated {
    let delegate = AppDelegate()
    NSApplication.shared.delegate = delegate
    _ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
}
```

**為什麼用 B？** `@main` + `@MainActor` 會有初始化時序衝突，`main.swift` 更明確可控。

---

## 7. 遇到的問題與解法

| 問題 | 原因 | 解法 |
|---|---|---|
| `@main` + `@MainActor` 衝突 | entry point 初始化時序問題 | 改用 `main.swift` |
| App 啟動後什麼都沒有 | `applicationDidFinishLaunching` 沒被呼叫 | 加 `print` debug，確認 entry point |
| Touch Bar 空白 | App 不是 frontmost | 點 menu bar 圖示讓 App 取得焦點 |
| `Main actor-isolated` 錯誤 | class 沒有標 `@MainActor` | 在 class 宣告前加 `@MainActor` |

---

## 8. 驗收標準

- [x] `⌘B` build 成功
- [x] `⌘R` 執行後 Dock **沒有**出現圖示
- [x] Menu bar 右上角出現 `⌨` 圖示
- [x] Console 看到 `🚀 App launched`
