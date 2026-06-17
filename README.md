# TouchBarTerminal

一個常駐 macOS 狀態列的迷你終端機，把 Touch Bar 變成持久存活的 zsh session。

## 核心概念

按下全域熱鍵 `⌃⌥Space` 後，焦點切到本 App，鍵盤輸入直接打進 PTY，Touch Bar 顯示提示符與最近一行輸出；再按一次熱鍵焦點還給原本的前景 App，但 PTY session 不死。

## 需求

- macOS 13.0+（Ventura）
- MacBook Pro with Touch Bar（Intel 2016–2020 或 M2 13" 2022）
- Xcode 16+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)：`brew install xcodegen`

## 快速開始

```bash
git clone https://github.com/eric20041027/TouchBarTerminal.git
cd TouchBarTerminal
xcodegen generate
open TouchBarTerminal.xcodeproj
```

Xcode 打開後按 `⌘R` 執行。

## 使用方式

| 操作 | 說明 |
|---|---|
| `⌃⌥Space` | 切換 Touch Bar 終端機焦點 |
| 鍵盤輸入 | 直接輸入指令 |
| `Enter` | 送出指令 |
| `↑ / ↓` | 瀏覽指令歷史 |
| `⌃C` | 中斷目前指令 |
| `← / →` | 移動游標 |
| `Tab` | 路徑自動補全（本地 PathCompleter） |
| `sudo` 等 | 密碼輸入顯示 🔒 ••••• |

## 設定檔

首次執行會自動建立 `~/.config/touchbarterminal/config.json`：

```json
{
  "shell" : "/bin/zsh",
  "fontSize" : 11,
  "cursorBlink" : true,
  "outputLines" : 2
}
```

| 欄位 | 說明 | 預設 |
|---|---|---|
| `shell` | 啟動的 shell | `/bin/zsh` |
| `fontSize` | Touch Bar 字型大小 | `11` |
| `cursorBlink` | 游標是否閃爍 | `true` |
| `outputLines` | 右側顯示幾行輸出 | `2` |

## 打包發佈

```bash
./scripts/build-release.sh
```

產出 `build/TouchBarTerminal.app`（Universal Binary，Intel + Apple Silicon），
並以 **ad-hoc 簽名**（免費 Apple ID，不需付費 Developer Program）。

### 別人下載後第一次開啟

ad-hoc 簽名未經 Apple notarization，Gatekeeper 會擋。第一次開啟：

1. 在 Finder **右鍵點 `TouchBarTerminal.app` → 打開**
2. 跳出警告時按「打開」（之後就能正常雙擊）

或在終端執行 `xattr -dr com.apple.quarantine TouchBarTerminal.app` 移除隔離屬性。

### 完整 notarization（需付費 Developer Program）

若加入 Apple Developer Program（$99/年），可用 Developer ID 憑證簽名 +
notarization，讓使用者免繞過 Gatekeeper。步驟見 `scripts/build-release.sh` 註解。

## 已知限制

- 不支援全螢幕程式（vim、htop、less）
- 不支援 ANSI 顏色（v1.0 純文字）
- 僅支援有實體 Touch Bar 的機型

## 專案架構

```
TouchBarTerminal/
├── App/          # 入口點、AppDelegate、AppConfig（JSON 設定）
├── UI/           # Touch Bar UI、Menu Bar 圖示
├── Session/      # TerminalSession、TerminalParser、PathCompleter、CommandHistory、AnsiStripper
├── PTY/          # PTYBridge（forkpty + DispatchSource）
└── Input/        # KeyboardInterceptor、GlobalHotKey
```

### 架構模式：MVVM + 混合輸入模式

```
PTYBridge  →  TerminalParser  →  TerminalSession  →  TouchBarController
（PTY I/O）   （解析輸出，純邏輯）  （ViewModel）        （Touch Bar UI）
                                      ↑
                              PathCompleter（本地 Tab 補全）
```

**混合輸入模式**：正常輸入（打字、←→、↑↓、Backspace）用本地 `inputBuffer`，
完全可控、游標不亂；只有 sudo 密碼輸入即時轉發給 zsh。Tab 用本地 `PathCompleter`，
不依賴 zsh 互動行（避免雙向同步的累加問題）。

## 開發進度

| Phase | 內容 | 狀態 |
|---|---|---|
| Phase 0 | 專案骨架、Menu Bar App | ✅ 完成 |
| Phase 1 | Touch Bar 靜態渲染 | ✅ 完成 |
| Phase 2 | PTY 橋接、真實 Shell 輸出 | ✅ 完成 |
| Phase 3 | 鍵盤輸入、Enter 送指令 | ✅ 完成 |
| Phase 4 | 指令歷史、Ctrl+C、Tab | ✅ 完成 |
| Phase 5 | 全域熱鍵、焦點切換（提前） | ✅ 完成 |
| Phase 6 | 收尾、游標動畫、設定檔、sudo 密碼 | ✅ 完成 |

## 學習講義

開發過程的知識點都記錄在 `docs/lectures/`：

- [Phase 0：環境建置](docs/lectures/phase0-environment.md)
- [Phase 1：Touch Bar UI](docs/lectures/phase1-touchbar-ui.md)
- [Phase 2：PTY 橋接](docs/lectures/phase2-pty-bridge.md)
- [完整技術 Spec（Phase 0–6）](docs/lectures/spec.md) — 含混合輸入模式、sudo 密碼、重構

## 參考資料

- [PRD.md](PRD.md) — 完整產品規格與架構設計
- [Apple NSTouchBar Documentation](https://developer.apple.com/documentation/appkit/nstouchbar)
- [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) — 未來版本的終端模擬器參考

---

## 系統架構

### MVVM 架構圖

```
[ main.swift ]
     │
     ▼
[ AppDelegate ]
     │
     ├──▶ [ StatusItemController ]   Menu Bar 圖示
     │          └── 訂閱 TerminalSession
     │
     ├──▶ [ TouchBarController ]     Touch Bar UI
     │          └── 訂閱 TerminalSession
     │
     └──▶ [ TerminalSession ]        ViewModel (狀態 + 輸入 buffer)
               │  @Published / Combine
               ├── [ TerminalParser ]   解析 zsh 輸出 → ParserEvent（純邏輯）
               ├── [ PathCompleter ]    本地 Tab 補全（FileManager）
               ├── [ CommandHistory ]   指令歷史
               ▼
          [ PTYBridge ]              forkpty() / Darwin read+write
               ▼
          [ /bin/zsh ]               子行程 (PTY slave)
```

### 輸出流（zsh → Touch Bar）

```
zsh 產生輸出
    │
    ▼
PTY slave fd
    │
    ▼
masterFD (可讀)
    │
    ▼
DispatchSource 觸發
    │
    ▼
PTYBridge.drain()
    │ 讀取原始 bytes
    ▼
String(data:encoding:)
    │ 轉成 Swift String
    ▼
onOutput?(str) callback
    │
    ▼
TerminalParser.feed(raw)（純邏輯）
    │ 剝除 ANSI、處理 \r\n、偵測 prompt / 密碼模式
    ▼
[ParserEvent]  .prompt(path) / .output(line) / .passwordPrompt ...
    │
    ▼
TerminalSession.apply(event)（@MainActor）
    │ 套到 @Published：currentPath / outputLines
    ▼
Combine sink → TouchBarController → Touch Bar 更新
```

### 輸入流（鍵盤 → 混合模式）

```
使用者敲鍵盤
    │
    ▼
NSEvent (keyDown)
    │
    ▼
KeyboardInterceptor（翻譯按鍵 → session 方法）
    │
    ├──▶ 一般字元 / ←→ / ↑↓ / Backspace
    │         └── 操作本地 inputBuffer（不送 zsh，游標完全可控）
    │             └── renderInputLine() → currentLine（Touch Bar 下排）
    │
    ├──▶ Tab → PathCompleter.complete()（本地 FileManager）
    │             ├── 唯一結果 → 補進 buffer
    │             └── 多個候選 → 顯示在右側
    │
    ├──▶ Enter → 送 buffer + \n 給 zsh，推進 CommandHistory
    │
    └──▶ sudo 密碼模式 → 即時轉發 zsh，自己數位數顯示 🔒 •••••
```

### 模組依賴圖

```
AppDelegate
    ├── AppConfig（JSON 設定）
    ├── TerminalSession
    │       ├── PTYBridge       → Darwin (C API)
    │       ├── TerminalParser  → AnsiStripper（解析輸出，純邏輯）
    │       ├── PathCompleter   → FileManager（本地 Tab 補全）
    │       └── CommandHistory  （指令歷史）
    ├── TouchBarController
    │       └── TerminalSession
    └── StatusItemController
            └── TerminalSession
```
