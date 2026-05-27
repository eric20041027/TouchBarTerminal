# TouchBarTerminal 專案開發預案

## 1. 專案概述 (Project Overview)
**TouchBarTerminal** 是一款針對配備 Touch Bar 的 MacBook Pro 所設計的 macOS 原生應用程式。
其核心目標是將 Touch Bar 轉化為一個獨立的、持續存活（Stateful）的微型終端機。使用者可透過點擊 Touch Bar 攔截實體鍵盤輸入，並在極限的螢幕高度內獲得即時的指令輸入與輸出回饋，實現不干擾主螢幕工作流的背景命令列操作。

## 2. 開發框架與技術堆疊 (Tech Stack)
* **開發語言：** Swift 5+
* **開發環境：** Xcode (macOS Native Development)
* **核心框架：**
  * `AppKit`: 處理 macOS 視窗、狀態列圖示與實體鍵盤事件攔截。
  * `NSTouchBar API`: 負責建構 Touch Bar 上的 UI 元件（文字輸入區塊與輸出顯示區塊）。
  * `Foundation`: 處理底層的 `Process` (行程建立) 與 `Pipe` (資料串流)。
* **架構模式：** MVC (Model-View-Controller) 或 MVVM，著重於將「PTY 行程狀態」與「Touch Bar 視圖」解耦。

## 3. 系統架構設計 (System Architecture)

### 3.1 視覺與 UI 層 (Frontend)
受限於 Touch Bar 高度 (約 60px)，UI 將採用極簡設計：
* **NSCustomTouchBarItem:** 作為主要的容器。
* **NSTextView (或自訂 CoreGraphics 渲染):**
  * **Layout:** 規劃為兩行顯示。上排顯示標準輸出 (`stdout` / `stderr`) 的最後一行；下排顯示目前的 Prompt 與使用者正在輸入的字元。
  * **Typography:** 強制使用等寬字體（如 Monaco 或 SF Mono）以確保排版整齊。

### 3.2 輸入攔截與控制層 (Event Handling)
* **全域/區域事件監聽 (Event Monitor):** 當 Touch Bar 的終端機區塊獲得焦點 (Focus) 時，透過 `NSEvent.addLocalMonitorForEvents` 攔截 `keyDown` 事件。
* **按鍵映射 (Key Mapping):** 將擷取到的字元動態附加到 UI 的輸入行，並在捕捉到 `Return (Enter)` 鍵時，將緩衝區的字串送入背景行程。

### 3.3 核心引擎與作業系統通訊 (Backend & IPC)
這是本專案的技術核心。為了維持如 `cd`, `export` 等指令的上下文狀態，不能採用單次執行的 Shell，必須建立偽終端機：
* **Pseudo-Terminal (PTY) Allocation:** 透過 C API `forkpty()` 或 Swift 封裝建立持續存活的 Shell Session (預設使用 `/bin/zsh`)。
* **Inter-Process Communication (IPC):**
  * 建立 File Descriptors (檔案描述子) 或 `Pipe` 來橋接 App 與 PTY。
  * **執行緒安全 (Thread Safety):** 由於非同步讀取 `stdout` 資料流與主執行緒更新 UI 會同時發生，必須確保資料寫入與讀取時的互斥 (Mutual Exclusion)，避免 Race Condition 導致 App 崩潰。

## 4. 開發階段規劃 (Phases)

* **Phase 1: UI 概念驗證 (PoC)**
  * 在 Xcode 中建立基礎 macOS App，成功在 Touch Bar 上渲染出靜態的文字視圖。
* **Phase 2: 鍵盤劫持與字元映射**
  * 實作 `NSEvent` 監聽，讓實體鍵盤的敲擊能正確顯示在 Touch Bar 的文字框內，並支援基本的 `Backspace` 刪除邏輯。
* **Phase 3: PTY 橋接與 I/O 串流**
  * 實作背景 `zsh` 行程，將 Phase 2 收集到的字串寫入 `stdin`，並非同步讀取 `stdout` 顯示回 Touch Bar。
* **Phase 4: 狀態列常駐與 UX 優化**
  * 隱藏 Dock 圖示，將 App 改為純 Menu Bar 狀態列應用。
  * 優化文字捲動邏輯與游標 (Cursor) 的閃爍動畫。