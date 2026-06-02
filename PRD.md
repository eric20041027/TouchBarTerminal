# TouchBarTerminal — 產品規格與架構藍圖 (v1.0)

> 本文件是基於 [TouchBarTerminal.md](TouchBarTerminal.md) 初步預案,經過需求釐清後產出的正式藍圖。實作前以本文件為準。

---

## 1. 產品定位

一個常駐 macOS 狀態列的迷你終端機,把 Touch Bar (約 60px 高) 變成一個**持久存活的 zsh session**。使用者按下全域熱鍵後,焦點瞬間切到本 App,鍵盤輸入直接打進 PTY,Touch Bar 顯示提示符與最近一行輸出;再按一次熱鍵焦點還給原本的前景 App,但 PTY session 不死、可以下次再回來。

**核心價值**:在不開新視窗、不切換工作區的前提下,快速跑一條指令(`git status`、`ls`、`pwd`、`docker ps`...)。

---

## 2. 已確認的關鍵決策 (Locked Decisions)

| 項目 | 決策 | 影響 |
|---|---|---|
| **顯示策略** | A1 — App 聚焦時顯示,搭配全域熱鍵快速切換焦點 | 純公開 API、可簽名分發、不會被 macOS 升級打壞 |
| **鍵盤輸入** | 點 Touch Bar(或按熱鍵)後 App 才接管鍵盤 | 不需要 Accessibility 權限、不會吃掉其他 App 的快捷鍵 |
| **Shell 範圍** | 單一持續 zsh session | App 啟動時 fork 一個 PTY,生命週期跟 App 一致 |
| **平台** | macOS 13+ (Ventura),Universal Binary (arm64 + x86_64);主測試機為 MacBook Pro M2 13" (2022,最後一台原生 Touch Bar 機型),同時相容 2016–2020 Intel Touch Bar MBP | 不處理 M1 Pro/Max 以後無 Touch Bar 機型、不處理 Pock |
| **輸出渲染** | 最後一行純文字,不解析 ANSI escape | MVP 規模小,後續可升級 |
| **MVP 範圍** | 最小可用集(含歷史、Ctrl+C、Tab、全域熱鍵) | 比純 PoC 更完整,但不是 iTerm 替代品 |

---

## 3. 不做什麼 (Non-Goals)

明確排除,避免 scope creep:
- 多 session / 分頁
- ANSI 顏色、完整 VT100 終端模擬
- 全螢幕程式 (vim、htop、less、nano)
- 滑鼠選取、複製貼上交給系統
- 設定面板 UI(v1 用 plist / JSON 設定)
- Apple Silicon 模擬支援
- 沙盒化 / App Store 上架(`LSUIElement` + accessory app 但暫不簽 sandbox)

---

## 4. 系統架構

### 4.1 模組劃分(MVVM)

```
┌─────────────────────────────────────────────────────────────┐
│                       AppDelegate                            │
│  - LSUIElement = YES (無 Dock 圖示)                          │
│  - 註冊 NSStatusItem (menu bar 圖示 + 狀態)                  │
│  - 註冊全域熱鍵 (Carbon RegisterEventHotKey)                 │
│  - 持有 TerminalSession (單例)                               │
└────────────┬────────────────────────────────────────────────┘
             │
   ┌─────────▼──────────┐         ┌──────────────────────────┐
   │  TerminalSession   │◀───────▶│  PTYBridge (Backend)     │
   │  (ViewModel)       │ Combine │  - forkpty()             │
   │  - inputBuffer     │/Async   │  - DispatchSource.read   │
   │  - lastOutputLine  │ stream  │  - 寫入 stdin            │
   │  - history (環狀)  │         │  - 處理 SIGCHLD          │
   │  - prompt 偵測     │         └──────────────────────────┘
   └─────────┬──────────┘
             │ @Published
             │
   ┌─────────▼──────────────────────────────────────────────┐
   │  TouchBarController (View)                              │
   │  - NSTouchBarDelegate                                   │
   │  - NSCustomTouchBarItem × 1 (主容器)                    │
   │  - 上排 NSTextField: 輸出行                              │
   │  - 下排 NSTextField: prompt + 當前輸入 + 游標           │
   └─────────┬──────────────────────────────────────────────┘
             │
   ┌─────────▼──────────────────────────────────────────────┐
   │  KeyboardInterceptor                                    │
   │  - NSEvent.addLocalMonitorForEvents (keyDown)           │
   │  - 只在 App 為 frontmost 時生效                          │
   │  - 字元 → inputBuffer / Enter → 送入 PTY                │
   │  - 特殊鍵: ↑↓ 歷史, ←→ 游標, Backspace, ⌃C, Tab        │
   └─────────────────────────────────────────────────────────┘
```

### 4.2 資料流(從鍵盤到 Touch Bar)

```
實體鍵盤
   │ NSEvent (keyDown)
   ▼
KeyboardInterceptor.handle(event)
   │
   ├─ printable → session.inputBuffer.append(char)
   │              session.objectWillChange ⤴
   │              TouchBarController 更新下排
   │
   ├─ Enter    → pty.write(buffer + "\n")
   │              session.history.push(buffer)
   │              buffer.clear()
   │
   ├─ ↑/↓     → buffer = history.previous/next()
   ├─ ⌃C      → pty.write(0x03)
   └─ Tab      → pty.write(0x09)  (交給 zsh 自己補全,我們不解析)

PTY stdout (背景執行緒)
   │ DispatchSource.makeReadSource
   ▼
PTYBridge.didRead(data)
   │ strip ANSI escape (簡易 regex)
   │ 累積到 lineBuffer,遇 \n 提取最後一行
   ▼
DispatchQueue.main.async {
    session.lastOutputLine = newLine
    session.prompt = detectPrompt(newLine)  // 簡易啟發式:含 $ 或 % 結尾
}
   │
   ▼
TouchBarController 更新上排
```

### 4.3 全域熱鍵 + 焦點切換

- 用 Carbon `RegisterEventHotKey` 註冊 `⌃⌥Space`(可改)。
- 觸發時:
  - 若 App **不是** frontmost → `NSApp.activate(ignoringOtherApps: true)`,Touch Bar 自動切到我們的。
  - 若 App **是** frontmost → `NSApp.hide(nil)`,焦點還給前一個 App。
- App 為 `LSUIElement = YES` + `accessoryActivationPolicy`,activate 時**不會跳出視窗、不會搶走 Dock 焦點動畫**,Touch Bar 上的迷你終端就是唯一的 UI。

### 4.4 PTY 實作要點

```swift
// 概念示意,不是最終 API
import Darwin

class PTYBridge {
    private var masterFD: Int32 = -1
    private var childPID: pid_t = 0
    private var readSource: DispatchSourceRead?
    private let writeQueue = DispatchQueue(label: "pty.write")

    func start(shell: String = "/bin/zsh") {
        var master: Int32 = 0
        let pid = forkpty(&master, nil, nil, nil)
        if pid == 0 {
            // child: exec shell with login flag
            execl(shell, shell, "-l", nil)
            exit(1)
        }
        self.masterFD = master
        self.childPID = pid
        startReading()
    }

    private func startReading() {
        let source = DispatchSource.makeReadSource(
            fileDescriptor: masterFD,
            queue: .global(qos: .userInitiated)
        )
        source.setEventHandler { [weak self] in self?.drain() }
        source.resume()
        self.readSource = source
    }

    func write(_ data: Data) {
        writeQueue.async { [fd = masterFD] in
            data.withUnsafeBytes { _ = Darwin.write(fd, $0.baseAddress, data.count) }
        }
    }
}
```

**執行緒安全**:
- PTY 讀取在 `userInitiated` 背景 queue,寫入在獨立序列 queue,UI 更新一律 `DispatchQueue.main`。
- `TerminalSession` 的 mutable state 只在 main thread 改;PTYBridge 透過 `@MainActor` 標記的回呼進入。

### 4.5 ANSI escape 處理(MVP 級)

不解析、只剝除,用簡單 regex(剝除 CSI 與 OSC 序列)。換行 `\n`/`\r\n` 切行,最後一行非空就當作要顯示的輸出。Prompt 偵測啟發式:該行含 `$ `、`% `、`# ` 結尾,就視為 prompt 行並抽出 prompt 字串。

> v1 限制:跑 `clear`、`ls --color`、`top` 會看起來怪。文件中明確說明只支援「會印單行回覆」的指令。

---

## 5. 檔案結構

```
TouchBarTerminal/
├── TouchBarTerminal.xcodeproj
├── TouchBarTerminal/
│   ├── App/
│   │   ├── AppDelegate.swift
│   │   ├── Info.plist                  # LSUIElement=YES
│   │   └── TouchBarTerminal.entitlements
│   ├── Session/
│   │   ├── TerminalSession.swift       # ViewModel
│   │   ├── CommandHistory.swift        # 環狀緩衝
│   │   └── AnsiStripper.swift
│   ├── PTY/
│   │   ├── PTYBridge.swift
│   │   └── forkpty_shim.h              # 必要時 bridging
│   ├── Input/
│   │   ├── KeyboardInterceptor.swift
│   │   └── GlobalHotKey.swift          # Carbon wrapper
│   ├── UI/
│   │   ├── TouchBarController.swift
│   │   ├── StatusItemController.swift  # menu bar 圖示
│   │   └── MonoFont.swift              # SF Mono 載入
│   └── Resources/
│       └── Assets.xcassets
└── TouchBarTerminalTests/
    ├── PTYBridgeTests.swift
    ├── CommandHistoryTests.swift
    ├── AnsiStripperTests.swift
    └── TerminalSessionTests.swift
```

---

## 6. 開發階段(更新版,取代原文件 §4)

### Phase 0 — 專案骨架
- Xcode 新建 macOS App、設定 `LSUIElement`、accessory activation policy、bundle identifier。
- 跑得起來:啟動後 Dock 沒有圖示、menu bar 有一個佔位圖示。
- **驗收**:啟動後只看到 menu bar 圖示,沒有視窗、沒有 Dock。

### Phase 1 — Touch Bar 靜態渲染
- 實作 `TouchBarController`,渲染兩行假資料(上排 `hello world`、下排 `% _`)。
- 等寬字體 + 灰底白字。
- **驗收**:App 在前景時,Touch Bar 看到兩行靜態文字。

### Phase 2 — PTY 橋接 + 單向輸出
- `PTYBridge` 用 `forkpty()` 起 zsh,把 stdout 收進 Swift。
- App 啟動時自動執行 `pwd`,Touch Bar 上排顯示當前路徑。
- 單元測試:`PTYBridgeTests` 驗證寫 `echo hi\n` 收到 `hi`。
- **驗收**:看到真實的 shell 輸出。

### Phase 3 — 鍵盤輸入 + Enter 送指令
- `KeyboardInterceptor` 接管 keyDown(僅 App 聚焦時)。
- 字元附加到 buffer,Backspace 刪除,Enter 送進 PTY。
- **驗收**:點選 Touch Bar 後,鍵盤輸入 `ls`+Enter,Touch Bar 上排顯示輸出。

### Phase 4 — 最小可用集
- 上下方向鍵叫出歷史(環狀緩衝,容量 100)。
- 左右方向鍵移動游標(下排顯示游標位置)。
- `⌃C` 送 SIGINT、`Tab` 透傳給 zsh、`⌃L` 視為 clear(我們清自己 buffer 即可)。
- ANSI escape 剝除。
- **驗收**:跑 `cd /tmp && ls`,輸出正常;`history` 用上下鍵叫得回來。

### Phase 5 — 全域熱鍵 + 焦點切換
- `GlobalHotKey` 用 Carbon 註冊 `⌃⌥Space`。
- 切回原 App 時 PTY 不死、buffer 不丟。
- menu bar 圖示有「連線中 / 已斷線」狀態。
- **驗收**:在其他 App 工作中按熱鍵,Touch Bar 變終端;再按一次,回原 App,session 連續。

### Phase 6 — 收尾
- 游標閃爍動畫、輸出捲動(若一行超過 Touch Bar 寬度,左右滾)。
- README、設定檔(`~/.config/touchbarterminal/config.json`:熱鍵、shell、字型大小)。
- 簽名(本地 dev cert 即可,不上架)。



---

## 7. 測試策略

| 測試類型 | 對象 | 工具 |
|---|---|---|
| Unit | `CommandHistory`、`AnsiStripper`、`TerminalSession` 純邏輯 | XCTest |
| Integration | `PTYBridge` 跑真實 zsh、寫入讀取一致性 | XCTest (`testEcho`、`testCd`) |
| Manual | Touch Bar UI、全域熱鍵、焦點切換 | 真機 (MacBook Pro M2 13" 2022 主測試機;Intel Touch Bar MBP 次要驗證) |

**目標覆蓋率**:核心邏輯模組 (Session / PTY / Ansi / History) 80%+。Touch Bar UI 不算覆蓋率(NSTouchBar 難以自動化)。

---

## 8. 主要風險與緩解

| 風險 | 機率 | 影響 | 緩解 |
|---|---|---|---|
| `NSTextField` 在 Touch Bar 渲染等寬字體有渲染瑕疵 | 中 | 中 | Phase 1 早期驗證;若有問題改用 `NSView` + Core Text 自繪 |
| PTY 在背景 thread 大量輸出造成 UI 卡頓 | 中 | 高 | 讀取端做 throttle(60Hz),只取「最後一行」減少 main thread 工作 |
| forkpty 在新版 macOS 行為改變 | 低 | 高 | 寫整合測試常跑;備案是改用 `posix_openpt` + manual fork |
| Carbon hotkey API 未來棄用 | 低 | 中 | 維持薄封裝(`GlobalHotKey.swift`),未來易切換到其他方案 |
| 焦點切回後鍵盤事件殘留 | 中 | 中 | `NSApp.didResignActiveNotification` 清空 modifier 狀態 |
| Apple 在未來 macOS 棄用 `NSTouchBar` API(M2 13" 之後無新硬體) | 中(長期) | 高 | 把 Touch Bar 渲染層獨立成模組,未來可替換為其他輸出(e.g. 浮動小視窗、Stream Deck) |

---

## 9. 成功標準 (Definition of Done)

v1.0 完成的判準:
- [ ] 一個 Intel MBP w/ Touch Bar 使用者下載 `.app` 後,5 分鐘內能在 Touch Bar 跑出第一條指令。
- [ ] 全域熱鍵切換焦點延遲 < 100ms,session 從不丟。
- [ ] 連續執行 1000 條 `echo` 指令,App 記憶體增長 < 50MB,不崩潰。
- [ ] 核心模組單元測試覆蓋 80%+,所有測試綠燈。
- [ ] README 包含安裝、熱鍵設定、已知限制(不支援 vim/top 等)。

---

## 10. 後續版本路線圖 (Out of v1.0 Scope)

- v1.1:設定面板 UI、自訂熱鍵、Touch Bar 上的常用指令 chip
- v1.2:簡易 ANSI 顏色(用 attributed string)
- v2.0:多 session、SwiftTerm 替換現有渲染、完整 VT100
- v2.1:命令補全候選清單顯示在 Touch Bar

---

*文件版本:1.0 · 建立日期:2026-05-26*
