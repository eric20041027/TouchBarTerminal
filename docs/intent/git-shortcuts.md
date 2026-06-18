# 意圖：Touch Bar git 快捷按鈕（v1.1 第一塊）

> 由 interview-me 產出並經使用者確認（2026-06-17）。

## Outcome
在 Touch Bar 上加一排 **git 快捷按鈕**（status / add / commit / push），
一點就跑，不用在 Touch Bar 上打長指令。

## User
使用者本人 —— 會用這個終端跑 git 的人。

## Why now
Touch Bar 打字慢，git 指令又長又固定（`git add . && git commit -m "..."`），
按鈕能發揮 Touch Bar「快捷鍵」的本質。

## Success
- 在 git repo 裡，Touch Bar 出現 git 按鈕
- 點 `status` 立刻看到狀態、點 `push` 直接推送
- 非 git 目錄時按鈕自動隱藏

## 技術學習點
- `NSButton` 放進 Touch Bar（`NSCustomTouchBarItem`）
- 偵測目錄是否為 git repo（用既有 `ProcessCWD` 拿真實 cwd）
- 動態顯示當前分支名
- 按鈕觸發指令送進 PTY

## 範圍
1. 偵測目前 cwd 是不是 git repo
2. 是 → Touch Bar 多一區 git 按鈕；否 → 隱藏
3. 按鈕：`git status`、`git add -A`、`git commit`、`git push`
4. （加分）顯示當前分支名

## Out of scope
- ANSI 顏色（下一塊再做）
- GUI diff 檢視器
- 合併衝突處理
- 多 repo

## 做法
照 TDD：git repo 偵測、分支解析這些純邏輯先寫測試 → RED → 實作 → GREEN。

## 待決定（實作時）
commit message 怎麼輸入：(a) 切回輸入框打字 (b) 固定訊息。
