# TouchBarTerminal — 開發約定

## 工作流程（重要）

**一律採用 TDD：先寫測試 → 跑到失敗（RED）→ 實作 → 跑到通過（GREEN）→ 重構。**
新增或修改功能前，先在 `TouchBarTerminalTests/` 寫對應測試，再動 production 程式碼。

### 跑測試（CLI，不必開 Xcode）
```bash
xcodebuild test -project TouchBarTerminal.xcodeproj -scheme TouchBarTerminal \
  -destination 'platform=macOS' \
  -only-testing:TouchBarTerminalTests/<TestClass>
```

## 學習導向

使用者是 Swift 初學者（Python 背景），偏好「我來寫，你來教」：
先解釋概念 → 使用者自己打程式碼 → review。
但純架構重構/多檔案修改可直接代勞，並事後解釋。

## 每個 Phase 完成後
1. 更新 `docs/lectures/` 講義（spec 風格：概覽表、程式碼、常見陷阱）
2. 更新 `README.md` 進度表
3. commit + push 到 GitHub（origin/main）

## 架構（MVVM + 混合輸入模式）

- `PTYBridge` — PTY I/O（forkpty + DispatchSource）
- `TerminalParser` — 純邏輯，解析 zsh 輸出 → ParserEvent（可測試）
- `PathCompleter` — 本地路徑補全（FileManager，不依賴 zsh）
- `TerminalSession` — ViewModel，狀態 + 輸入 buffer 管理
- `TouchBarController` / `StatusItemController` — UI

**輸入採混合模式**：正常輸入用本地 inputBuffer（游標/箭頭/歷史完全可控），
只有 sudo 密碼輸入即時轉發給 zsh。Tab 用本地 PathCompleter。
（教訓：別自己重寫終端的行內編輯/游標控制，會無止境打地鼠。）

## 平台
macOS 13+，MacBook Pro M2 13"（2022，最後一台有 Touch Bar）。
Universal Binary（arm64 + x86_64）。

## 工具鏈
- Xcode 16、XcodeGen（改檔案結構後跑 `xcodegen generate`）
- 新增 Swift 檔案後務必 `xcodegen generate` 才會進專案
