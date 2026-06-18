# git 快捷按鈕 — 進度與決策

> 更新：2026-06-18。承接 docs/intent/git-shortcuts.md。

## 已完成

- **塊 1：GitStatus**（commit b2884d7，已 push）
  - `GitStatus.branchName(fromHEAD:)` 純解析 `.git/HEAD`
  - `GitStatus.detect(at:)` 往上找 `.git/HEAD`，回 isRepo + branch
  - GitStatusTests 7 個全綠
- **塊 2+3：git 按鈕 UI（共存模式）**（本分支已 push）
  - TerminalSession：`@Published gitBranch`、`updateGitBranch()`（用 ProcessCWD
    真實 cwd + GitStatus.detect）、`runCommand(_:)`，純函式 `commandBytes(for:)`
    （nonisolated，攜帶 ⌃U + 指令 + 換行）有單元測試。
  - TouchBarController：`gitStack`（分支 label + status/add/commit/push 四個
    NSButton），訂閱 `$gitBranch` → repo 內才顯示。輸出欄改為可壓縮，git 按鈕
    放進 Touch Bar 剩餘空間。
  - 按鈕指令藏在 `NSButton.identifier`，點擊 → `session.runCommand(...)`。

## 關鍵決策：共存模式（option b），不走 system modal

舊 wip/git-buttons 分支曾嘗試用 `presentSystemModalTouchBar:` + 私有 DFR API
蓋掉系統 Control Strip，讓 Touch Bar 佔滿整條，但出現 3 個 bug，根因其實是同一個：

- **system modal 把 Touch Bar 控制權交給系統層 → App 失去 key 狀態。**
- 鍵盤輸入用的是 `NSEvent.addLocalMonitorForEvents`（**local** monitor，只在
  App 為 key 時才收事件）→ modal 下打不了字（原 bug #3）。
- Control Strip 隱藏（DFR）與三態循環（bug #1、#2）也都是跟系統 modal 生命週期
  打地鼠的副作用。

依 CLAUDE.md「別自己重寫終端、別跟系統打地鼠」的教訓，**放棄 modal/DFR 路線**，
改回一般 App Touch Bar（純公開 API，App 維持 key → 輸入正常），git 按鈕擠進
終端版面的剩餘空間。

**取捨**：右側系統 Control Strip（亮度/音量/Siri）仍在，git 按鈕區較窄；
換來穩定、無私有 API、輸入不會壞。已與使用者確認採此方向。

## 測試狀態

- 33 個測試全綠（GitStatus 7 + RunCommand 3 + 其餘 23）。
- UI 顯示/隱藏靠真機驗證（無單元測試）。
- 跑測試：
  `xcodebuild test -project TouchBarTerminal.xcodeproj -scheme TouchBarTerminal -destination 'platform=macOS'`

## 待決定 / 下一塊

- commit message 輸入方式（intent 的「待決定」）：目前 `git commit` 不帶 `-m`，
  會在 zsh 開編輯器；之後可評估切回輸入框打訊息。
- ANSI 顏色、GUI diff、合併衝突：見 intent 的 out of scope。

## 環境

- 真機：MacBook Pro M2 13"。改檔案結構後跑 `xcodegen generate`。
- TDD：純邏輯先寫測試再實作（見 CLAUDE.md）。
