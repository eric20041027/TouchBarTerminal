# git 快捷按鈕 — 進度與決策

> 更新：2026-06-19。承接 docs/intent/git-shortcuts.md。

## 已完成

- **塊 1：GitStatus**（commit b2884d7，已 push）
  - `GitStatus.branchName(fromHEAD:)` 純解析 `.git/HEAD`
  - `GitStatus.detect(at:)` 往上找 `.git/HEAD`，回 isRepo + branch
  - GitStatusTests 7 個全綠
- **塊 2+3：git 按鈕 UI（共存模式）**（已 push）
  - TerminalSession：`@Published gitBranch`、`updateGitBranch()`（用 ProcessCWD
    真實 cwd + GitStatus.detect）、`runCommand(_:)`，純函式 `commandBytes(for:)`
    （nonisolated，攜帶 ⌃U + 指令 + 換行）有單元測試。
  - 按鈕指令藏在 `NSButton.identifier`，點擊 → `session.runCommand(...)`。

- **塊 4：模式切換（真機驗證後改版）**（已 push）
  - 真機發現「共存擠版面」不可行：`ls` 等寬輸出會把 git 按鈕推到右側系統
    Control Strip 後面，點不到。改成**互斥的兩種模式**：
  - `GitPanelMode`（純邏輯狀態機，4 測試）：`.output` / `.git`，`toggled()`、
    `afterRepoChange(isRepo:)`（離開 repo 強制回 `.output`）。
  - TouchBarController：左上 **⎇ git 圖示鈕**（SF Symbol `arrow.triangle.branch`，
    repo 內才出現）切換右側「終端輸出」⇄「git 按鈕區」，`applyPanelMode()` 控制
    兩者互斥顯示 → 永不互相擠壓。點 git 動作鈕後 `panelMode = .output` 自動切回，
    立刻看到結果。

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

**取捨**：右側系統 Control Strip（亮度/音量/Siri）仍在；換來穩定、無私有 API、
輸入不會壞。版面擠壓問題由「塊 4 模式切換」解決（輸出與 git 按鈕互斥顯示）。

## 已知陷阱（真機踩過）

- **`git status -sb` 輸出被吞**：短格式第一行 `## main...origin/main` 的 `##`
  撞到 TerminalParser 的 prompt 判斷（`#` 被當 prompt 符號）→ 該輸出被當 prompt
  丟掉。**status 按鈕改用純 `git commit`/`git status`**（輸出無 prompt 符號）。
  根本問題是 parser 的 `[%$#]` heuristic 太貪，但改它有回歸風險，故先繞過。
- **驗證時務必只留單一實例**：⌃⌥Space 用 Carbon `RegisterEventHotKey`（先註冊先贏），
  Xcode debug 實例或舊 build 會搶走熱鍵，導致「改了沒效果」的假象。
  測試前 `pkill -9 -f "MacOS/TouchBarTerminal"`，Xcode 要按 ■ Stop。

## 測試狀態

- 41 個測試全綠（GitStatus 7 + RunCommand 3 + GitPanelMode 4 + CommitCommand 4 + 其餘 23）。
- UI 顯示/模式切換/commit 流程靠真機驗證（狀態機與指令組裝有單元測試）。
- 跑測試：
  `xcodebuild test -project TouchBarTerminal.xcodeproj -scheme TouchBarTerminal -destination 'platform=macOS'`

## 塊 5：commit message 輸入模式（已 push）

intent 的「待決定」已定案：**選 (a) 切回輸入框打訊息**。

- 點 commit 按鈕 → 進入 commit 訊息模式：左側暫時變訊息輸入框（重用 inputBuffer，
  打字/Backspace/游標都可用，prompt 顯示 `commit ▸`）。
- Enter → 訊息非空 → 跑 `git commit -m "<訊息>"`、回正常模式、右側顯示結果；
  空訊息 = 取消。⌃C 也可取消（訊息只在本地 buffer，沒送 zsh）。
- `commitCommand(message:)` 純函式組裝並跳脫指令（先反斜線再雙引號、修空白），
  4 個單元測試。commit 模式下停用指令歷史（避免蓋掉訊息）。

## 待決定 / 下一塊

- ANSI 顏色、GUI diff、合併衝突：見 intent 的 out of scope。
- `TerminalParser` 的 `[%$#]` heuristic 偏貪（status 已繞過 `-sb`），要更豐富 git
  輸出時再硬化。

## 環境

- 真機：MacBook Pro M2 13"。改檔案結構後跑 `xcodegen generate`。
- TDD：純邏輯先寫測試再實作（見 CLAUDE.md）。
