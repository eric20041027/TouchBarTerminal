# 意圖：Touch Bar 的整體方向（重新校準）

> 由 interview-me 產出並經使用者確認（2026-06-19）。
> 這份**推翻**了舊 PRD 的 v1.1（設定面板/自訂熱鍵）、v1.2（ANSI）、v2.0（多 session/SwiftTerm）路線圖——那些是「為了功能而功能」，不是使用者真正想要的。

## 背景：為什麼重新規劃

git 按鈕（v1.1）做完後，使用者想重新想「Touch Bar 該幫我做什麼最有價值」。
interview-me 過程揭露的真相：

- 使用者**日常活在 PyCharm + Xcode + Claude 桌面版**三個 GUI app，**終端不是主場**。
  這個 TouchBarTerminal 終端 App 其實**偶爾才用**。
- 想找痛點時舉了「Xcode ⌘R 運行很麻煩」，但一問才發現：Run 鍵 Xcode 本來就有，
  **真正的問題是使用者根本沒注意到 Touch Bar 上已有的東西**。
- 關鍵領悟：**問題從來不是 Touch Bar 缺功能，是 Touch Bar 不在使用者的注意力習慣裡。**
  再多靜態按鈕，使用者不會低頭看，都是白做。

## Outcome

把這台 M2 的 Touch Bar 變成一條「**會主動變化、瞄一眼就有用、而且只有這台機器做得到**」的
即時資訊 + 快捷列，讓使用者**養成真的會去看它**的習慣——而不是再多塞靜態按鈕。

## User

使用者本人：在 PyCharm / Xcode / Claude 桌面版之間工作、擁有一台稀有
（最後一代有 Touch Bar 的）M2 13" 的開發者，Python 背景、學 Swift 中。

## Why now

git 按鈕證明了「Touch Bar 能放自訂、會變化的東西」這條路可行；
但使用者發現真正的障礙是注意力習慣，光加功能解決不了，所以要換思路。

## Success

使用者會**主動瞄 Touch Bar**（像看狀態列一樣），因為上面有他當下在意、
且別處看不到的即時資訊；而且這東西**獨特到他想拿給別人看**。

## 主要目標（使用者排序）

1. **(a) 養成真的會用 Touch Bar 的習慣** —— 重點是「怎麼讓他願意低頭看」：
   放會主動變化、會提醒、瞄一眼就有用的即時資訊，而非靜態按鈕。
2. **(c) 做出獨特 / 想炫耀的東西** —— 只有這台 + 只有他會做的酷點子。
3. （b 學 Swift/macOS 是副產品——反正做就會學到，不是主要驅動。）

## Constraint

- 純公開 API、Touch Bar 單行高度、要穩定（不跟系統 Control Strip 打架——
  見 [[git-shortcuts-status.md]] 記取的教訓：別走 system modal / 私有 DFR）。
- 使用者是 Swift 初學者，複雜度要可學、可控（TDD、純邏輯先測，見 CLAUDE.md）。
- 終端 App 是目前唯一的實驗載體；形態未來可能要變（甚至不再是「終端」）。

## Out of scope

- 「為了功能而功能」的靜態按鈕清單。
- 取代日常的 GUI app（PyCharm/Xcode/Claude）。
- 通用終端機 / 完整 VT100 / 多 session 的野心（舊 PRD v2.0，已放棄）。

## 下一步

用 `idea-refine` 針對「會主動變化、瞄一眼有用、只有這台做得到」生具體點子，使用者挑。
