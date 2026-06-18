# git 快捷按鈕 — 進度與待解問題（給新 session 接手）

> 更新：2026-06-17。承接 docs/intent/git-shortcuts.md。

## 已完成（已 commit b2884d7）
- **塊 1：GitStatus**（已 push）
  - `GitStatus.branchName(fromHEAD:)` 純解析 .git/HEAD
  - `GitStatus.detect(at:)` 往上找 .git/HEAD，回 isRepo + branch
  - GitStatusTests 7 個全綠

## 已實作但「未 commit」（在工作區，有問題）
- **塊 2：git 按鈕 UI**
  - TerminalSession：`@Published var gitBranch`、`updateGitBranch()`（用 ProcessCWD 真實 cwd）、`runCommand(_:)`
  - TouchBarController：`gitStack`（分支 label + status/add/commit/push 四個 NSButton），訂閱 gitBranch 控制 isHidden
  - 按鈕指令藏在 `NSButton.identifier`，點擊 → `session.runCommand(...)`
- **塊 3（嘗試中，有 bug）：佔滿整條 Touch Bar**
  - TouchBarController：`presentFullWidth()` / `dismiss()` 用 runtime 呼叫
    `presentSystemModalTouchBar:systemTrayItemIdentifier:`（class method，已確認可呼叫）
  - AppDelegate.toggleFocus：present/dismiss 綁進去
  - 新檔 `UI/DFR.swift`：dlsym 取 DFR 函式隱藏 Control Strip

## 目前的 BUG（待新 session 解）
1. **Control Strip 沒藏**：
   - `presentSystemModalTouchBar:` 成功呼叫（Console 印 ✅），左側出現 ⊗ 關閉鈕，
     代表 system modal 啟動，但右側系統按鈕（亮度/音量/Siri）仍在。
   - DFR 嘗試：`DFRSetStatusBarControlStripPresence` 不存在；
     `DFRElementSetControlStripPresenceForIdentifier(CFString, Bool)` 找得到但
     逐個關元件（com.apple.system.brightness 等）無效。
   - **下一步方向**：可能要用 present 的 placement 參數版（placement=1 蓋滿），
     或參考 Pock 原始碼的正確 DFR 呼叫序列。
2. **三狀態循環**：⌃⌥Space 現在在「modal開 / modal關 / 一般」三態間循環，
   不是乾淨的兩態切換。根因：toggleFocus 用 NSApp.isActive 判斷，
   但 system modal + appDidBecomeActive 通知讓狀態時序打架。
3. **modal 狀態無法輸入**：左邊 ⊗ 的 modal 狀態下，鍵盤輸入進不去
   （NSEvent local monitor 可能因 modal 失焦而收不到）。

## 關鍵檔案
- TouchBarTerminal/UI/TouchBarController.swift（present/dismiss、gitStack）
- TouchBarTerminal/UI/DFR.swift（Control Strip 控制，目前無效）
- TouchBarTerminal/App/AppDelegate.swift（toggleFocus）
- TouchBarTerminal/Session/TerminalSession.swift（gitBranch、runCommand）

## 決策背景
- 使用者選 system modal 佔滿整條（蓋 Control Strip），接受用 private DFR API。
- 但 modal 帶來輸入/狀態循環問題。新 session 可重新評估：
  (a) 修好 system modal（解 3 個 bug），或
  (b) 回共存模式 + 版面壓縮（純公開 API，穩定，git 按鈕放剩餘空間）。

## 測試狀態
- 30 個測試全綠（含 GitStatus 7）。UI/modal 部分無單元測試，靠真機。
- 跑測試：xcodebuild test -project TouchBarTerminal.xcodeproj -scheme TouchBarTerminal -destination 'platform=macOS'

## 環境
- 真機：MacBook Pro M2 13"。改檔案後跑 xcodegen generate。
- TDD：先寫測試再實作（見 CLAUDE.md）。
