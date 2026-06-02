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
| `Tab` | 自動補全（由 zsh 處理） |

## 已知限制

- 不支援全螢幕程式（vim、htop、less）
- 不支援 ANSI 顏色（v1.0 純文字）
- 僅支援有實體 Touch Bar 的機型

## 專案架構

```
TouchBarTerminal/
├── App/          # 入口點、AppDelegate
├── UI/           # Touch Bar UI、Menu Bar 圖示
├── Session/      # ViewModel（TerminalSession）
├── PTY/          # Shell 行程管理（PTYBridge）
└── Input/        # 鍵盤攔截、全域熱鍵
```

### 架構模式：MVVM

```
PTYBridge  →  TerminalSession  →  TouchBarController
（Shell）      （ViewModel）        （Touch Bar UI）
```

## 開發進度

| Phase | 內容 | 狀態 |
|---|---|---|
| Phase 0 | 專案骨架、Menu Bar App | ✅ 完成 |
| Phase 1 | Touch Bar 靜態渲染 | 🔄 進行中 |
| Phase 2 | PTY 橋接、真實 Shell 輸出 | ⏳ 待開始 |
| Phase 3 | 鍵盤輸入、Enter 送指令 | ⏳ 待開始 |
| Phase 4 | 指令歷史、Ctrl+C、Tab | ⏳ 待開始 |
| Phase 5 | 全域熱鍵、焦點切換 | ⏳ 待開始 |
| Phase 6 | 收尾、游標動畫、設定檔 | ⏳ 待開始 |

## 學習講義

開發過程的知識點都記錄在 `docs/lectures/`：

- [Phase 0：環境建置](docs/lectures/phase0-environment.md)
- [Phase 1：Touch Bar UI](docs/lectures/phase1-touchbar-ui.md)

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
     └──▶ [ TerminalSession ]        ViewModel (狀態中心)
               │  @Published / Combine
               ▼
          [ PTYBridge ]              Backend
               │  forkpty() / Darwin read+write
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
TerminalSession（@MainActor）
    │
    ├──▶ AnsiStripper.strip()      剝除 ANSI codes
    ├──▶ lastMeaningfulLine()      取最後一行
    └──▶ lastOutputLine = line     @Published 觸發
              │
              ▼
         Combine sink
              │
              ▼
    TouchBarController
              │
              ▼
    outputLabel.stringValue        Touch Bar 上排更新
```

### 輸入流（鍵盤 → zsh）

```
使用者敲鍵盤
    │
    ▼
NSEvent (keyDown)                ← Phase 3 實作
    │
    ▼
KeyboardInterceptor
    │
    ├──▶ 一般字元 → session.appendToBuffer(char)
    │                    │
    │                    ▼
    │              inputBuffer @Published
    │                    │
    │                    ▼
    │           inputLabel 更新（Touch Bar 下排）
    │
    └──▶ Enter → session.submitInput()
                        │
                        ▼
                 PTYBridge.writeString("ls\n")
                        │
                        ▼
                 Darwin.write(masterFD, ...)
                        │
                        ▼
                      zsh 執行
```

### 模組依賴圖

```
AppDelegate
    ├── TerminalSession
    │       ├── PTYBridge       → Darwin (C API)
    │       ├── AnsiStripper
    │       └── CommandHistory
    ├── TouchBarController
    │       └── TerminalSession
    └── StatusItemController
            └── TerminalSession
```
