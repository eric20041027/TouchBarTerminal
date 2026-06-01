# Phase 2 — PTY 橋接：讓 Touch Bar 顯示真實終端輸出

## 學習目標

完成本章後你將能夠：

1. 解釋什麼是 PTY，以及它和普通 pipe 的差別
2. 使用 `forkpty()` 正確 fork 出一個子 shell
3. 用 `DispatchSource` 非同步讀取 PTY 輸出
4. 用 Regex 清洗 ANSI escape sequence
5. 透過 Combine `@Published` 把終端輸出推送到 UI

---

## 1. 背景知識：什麼是 PTY？

### 1.1 Terminal、PTY、Shell 的關係

```
┌─────────────────────┐
│   你的 App (我們)    │  ← master side (masterFD)
│   TouchBarTerminal  │
└─────────┬───────────┘
          │  PTY pair（virtual wire）
┌─────────▼───────────┐
│   zsh / bash        │  ← slave side (slaveFD)
│   子 process        │
└─────────────────────┘
```

- **PTY** = Pseudo-TTY（虛擬終端）。它是 kernel 提供的一對 file descriptor：
  - **master side**：我們的程式讀寫的那端
  - **slave side**：子 process（zsh）看到的那端，它以為自己連接到真實終端
- 為什麼不直接用 `pipe()`？因為 zsh 偵測到 stdout 不是 TTY 時，會關掉 prompt、顏色、行緩衝，PTY 讓它以為自己在真正的終端機裡執行。

### 1.2 流程概覽

```
App 啟動
  └─ forkpty() ──┬─ parent: 拿到 masterFD，繼續執行 Swift 程式碼
                 └─ child:  exec("/bin/zsh")，替換成 zsh process

parent 持續:
  masterFD readable → read() → ANSI strip → @Published → Touch Bar 更新
  使用者輸入        → write() → masterFD → zsh 收到並執行
```

---

## 2. POSIX API 詳解

### 2.1 `forkpty()`

**標頭**：`<util.h>`（Swift：`import Darwin`，macOS 已內建）

```c
// C 函數簽名
pid_t forkpty(int *amaster,
              char *name,
              const struct termios *termp,
              const struct winsize *winp);
```

| 參數 | 型別 | 說明 |
|------|------|------|
| `amaster` | `*Int32` | **輸出參數**：函數把 master FD 填進這個位置 |
| `name` | `*CChar?` | 填入 slave 裝置路徑（不需要可傳 `nil`） |
| `termp` | `*termios?` | 初始 terminal 屬性（傳 `nil` 使用 kernel 預設值） |
| `winp` | `*winsize?` | 初始視窗大小（行數、欄數） |

**回傳值**：

| 值 | 代表 | 你應該做什麼 |
|----|------|-------------|
| `> 0` | 你是 **parent process**，值是子 process 的 PID | 繼續執行 app 邏輯 |
| `== 0` | 你是 **child process**（剛被 fork 出來） | 呼叫 `exec` 替換成 zsh |
| `< 0` | fork 失敗 | 處理錯誤，印出 `errno` |

**Swift 完整用法：**

```swift
import Darwin

var masterFD: Int32 = -1
var ws = winsize(ws_row: 1, ws_col: 80, ws_xpixel: 0, ws_ypixel: 0)

// &masterFD：傳入 masterFD 的記憶體位址，讓 forkpty 填入結果
// &ws：傳入 winsize 結構的記憶體位址
let pid = forkpty(&masterFD, nil, nil, &ws)

switch pid {
case -1:
    // fork 失敗，errno 裡有詳細錯誤碼
    perror("forkpty failed")

case 0:
    // ─────────────────────────────
    // 這段程式碼在 child process 執行
    // ─────────────────────────────
    // execle 把 child 替換成 zsh
    execle("/bin/zsh", "zsh", "--login", nil, environ)
    // 只有 exec 失敗才會執行到這裡
    exit(1)

default:
    // ──────────────────────────────
    // 這段程式碼在 parent process 執行
    // ──────────────────────────────
    // pid 是子 process 的 PID
    // masterFD 現在是有效的 file descriptor
    print("Child PID: \(pid), masterFD: \(masterFD)")
    startReading()  // 開始非同步讀取 PTY 輸出
}
```

> **關鍵概念**：`forkpty()` 呼叫一次，但「回傳兩次」——在 parent 和 child 各回傳一次。parent 繼續執行 Swift 程式，child 被 `exec` 替換成 zsh。

---

### 2.2 `winsize` 結構

```c
struct winsize {
    unsigned short ws_row;    // 終端行數（height，幾行文字）
    unsigned short ws_col;    // 終端欄數（width，每行幾個字元）
    unsigned short ws_xpixel; // 像素寬（通常設 0，讓終端忽略）
    unsigned short ws_ypixel; // 像素高（通常設 0，讓終端忽略）
};
```

```swift
// Touch Bar 是單行顯示，設 1 行、80 欄
var ws = winsize(ws_row: 1, ws_col: 80, ws_xpixel: 0, ws_ypixel: 0)
```

---

### 2.3 `execle()`

```c
// C 函數簽名
int execle(const char *path,
           const char *arg0,
           ...   // 更多 args，必須以 NULL 結尾
           NULL,
           char *const envp[]);
```

- **作用**：讓 child process 「變成」指定的程式（zsh）
- `exec` 成功後，**以下程式碼永遠不會執行**，因為 process 映像已被完全替換
- 只有 `exec` 失敗（找不到檔案等），才會繼續執行後面的 `exit(1)`

| 參數 | 說明 |
|------|------|
| `/bin/zsh` | 要執行的程式路徑 |
| `"zsh"` | 傳給程式的 `argv[0]`（慣例是程式名稱） |
| `"--login"` | 讓 zsh 讀取 `~/.zshrc`，環境完整 |
| `nil` | **必須**以 `nil` 結束 varargs（C 的慣例） |
| `environ` | 繼承 parent process 的環境變數 |

```swift
// child process 裡執行：
execle("/bin/zsh", "zsh", "--login", nil, environ)
// ↑ 如果成功，這一行之後的 swift 程式碼不會被執行
exit(1)
```

---

### 2.4 `Darwin.read()` — 從 PTY 讀取輸出

```c
// C 函數簽名
ssize_t read(int fd, void *buf, size_t count);
```

| 參數 | 說明 |
|------|------|
| `fd` | file descriptor（我們的 `masterFD`） |
| `buf` | 緩衝區指標，讀到的資料存進這裡 |
| `count` | 最多讀幾個 bytes |

**回傳值**：

| 值 | 意義 |
|----|------|
| `> 0` | 實際讀到的 bytes 數 |
| `== 0` | EOF（子 process 關閉了 PTY） |
| `< 0` | 錯誤（`errno == EAGAIN` 表示暫時無資料） |

**Swift 用法：**

```swift
private func drain() {
    // 建立 4096 bytes 的緩衝區（UInt8 陣列）
    var buffer = [UInt8](repeating: 0, count: 4096)

    // Darwin.read：加 Darwin. 前綴避免和 Swift stdlib 衝突
    // &buffer：傳入陣列的記憶體位址
    // buffer.count：最多讀 4096 bytes
    let n = Darwin.read(masterFD, &buffer, buffer.count)

    guard n > 0 else { return }  // n == 0 是 EOF，n < 0 是錯誤

    // 只取前 n 個 bytes 轉成 Data
    let data = Data(buffer.prefix(n))

    // 從 UTF-8 bytes 解碼成 Swift String
    guard let text = String(data: data, encoding: .utf8) else { return }

    // 切回 main thread 更新 UI
    DispatchQueue.main.async {
        self.onOutput?(text)
    }
}
```

---

### 2.5 `Darwin.write()` — 寫入輸入到 PTY

```c
// C 函數簽名
ssize_t write(int fd, const void *buf, size_t count);
```

```swift
func writeString(_ input: String) {
    guard let data = input.data(using: .utf8) else { return }
    writeData(data)
}

func writeData(_ data: Data) {
    guard masterFD >= 0 else { return }

    // 在 serial queue 執行，確保寫入操作不會交錯
    writeQueue.async { [fd = self.masterFD] in
        data.withUnsafeBytes { rawBuffer in
            guard let ptr = rawBuffer.baseAddress else { return }
            // count：要寫入的 bytes 數
            _ = Darwin.write(fd, ptr, data.count)
        }
    }
}
```

> **為什麼用 `[fd = self.masterFD]`**：在 async closure 裡直接用 `self.masterFD` 會造成 retain cycle，把 FD 值先複製出來更安全。

---

### 2.6 `kill()` — 終止子 process

```c
// C 函數簽名
int kill(pid_t pid, int sig);
```

| Signal 常數 | 數值 | 說明 |
|------------|------|------|
| `SIGTERM` | 15 | 禮貌性終止：讓程式有機會清理資源後退出 |
| `SIGKILL` | 9 | 強制終止：kernel 直接結束，程式無法攔截 |
| `SIGHUP` | 1 | 終端掛斷：zsh 通常會在收到後自動退出 |

```swift
func stop() {
    readSource?.cancel()     // 停止 DispatchSource 監聽
    readSource = nil

    if childPID > 0 {
        kill(childPID, SIGTERM)   // 請 zsh 正常結束
    }
    if masterFD >= 0 {
        Darwin.close(masterFD)   // 釋放 file descriptor
    }

    // 重設，避免 double-close
    masterFD = -1
    childPID = 0
}
```

---

## 3. GCD（Grand Central Dispatch）API 詳解

### 3.1 為什麼需要 GCD？

`read()` 是 **blocking call**：如果沒有資料可讀，它會卡住等。若在 main thread 上呼叫，整個 UI 就凍結了。

解法：`DispatchSource` 讓 kernel 幫我們監聽「FD 什麼時候有資料可讀」，只在真的有資料時才呼叫 `read()`，不佔用 main thread。

### 3.2 `DispatchSource.makeReadSource()`

```swift
// 語法：
let source = DispatchSource.makeReadSource(
    fileDescriptor: masterFD,                    // 要監聽的 FD
    queue: .global(qos: .userInitiated)          // 事件 handler 在哪個 queue 執行
)

// ──── 設定 handler ────

// 有資料可讀時觸發（這裡適合呼叫 read()）
source.setEventHandler { [weak self] in
    self?.drain()
}

// source 被取消時觸發（適合做清理，例如 close FD）
source.setCancelHandler { [fd = masterFD] in
    Darwin.close(fd)  // 在這裡 close，確保 source 不再用到 FD 之後才關閉
}

// ──── 啟動 ────
// 建立後預設是 suspended（暫停），必須呼叫 resume() 才開始監聽
source.resume()

// ──── 停止 ────
// 會先等 eventHandler 執行完，再呼叫 cancelHandler
source.cancel()
```

> **常見錯誤**：忘記呼叫 `resume()`，導致永遠收不到事件。

### 3.3 `DispatchQueue` 詳解

```swift
// ── Global background queue（系統管理的 thread pool）──
DispatchQueue.global(qos: .userInitiated)  // 用戶觸發，需快速回應
DispatchQueue.global(qos: .background)     // 低優先，不影響 UI

// ── 自訂 Serial Queue（每次只跑一個 task，保證順序）──
let writeQueue = DispatchQueue(
    label: "com.tbt.pty.write",   // 識別名（用 reverse-DNS 格式，方便 debug）
    qos: .userInitiated
)

// ── Main Queue（UI 更新必須在這裡）──
DispatchQueue.main.async {
    self.lastOutputLine = newLine   // @Published 屬性更新
}
```

**QoS（Quality of Service）等級說明**：

| QoS | 用途 | Touch Bar 專案對應 |
|-----|------|------------------|
| `.userInteractive` | 直接影響畫面，最高優先 | 不需要 |
| `.userInitiated` | 使用者觸發，需快速回應 | PTY 讀寫 |
| `.utility` | 長時間背景工作 | 不需要 |
| `.background` | 完全不需要使用者等待 | 不需要 |

**async vs sync**：

```swift
queue.async { /* 不等完成，繼續執行 */ }
queue.sync  { /* 等 block 完成才繼續 */ }  // 慎用：可能 deadlock
```

---

## 4. ANSI Escape Sequence 清洗

### 4.1 什麼是 ANSI escape sequence？

zsh 輸出的文字夾雜控制碼，例如：

```
原始輸出（含控制碼）：
  \x1B[1;32m%\x1B[0m /Users/smallfire \x1B[0m

清洗後（純文字）：
  % /Users/smallfire
```

常見的 escape sequence 類型：

| 類型 | 格式 | 例子 | 作用 |
|------|------|------|------|
| SGR（顏色/樣式） | `\x1B[n;nm` | `\x1B[1;32m` | 綠色粗體 |
| 游標移動 | `\x1B[n;nH` | `\x1B[1;1H` | 移游標到第 1 行第 1 欄 |
| 清除螢幕 | `\x1B[2J` | `\x1B[2J` | 清除整個螢幕 |
| OSC（視窗標題） | `\x1B]0;text\x07` | `\x1B]0;~\x07` | 設定標題為 ~ |
| Reset | `\x1B[0m` | `\x1B[0m` | 重設所有樣式 |

其中 `\x1B` 就是 `ESC` 字元（ASCII 27）。

### 4.2 Regex 模式拆解

```swift
private static let pattern =
    #"\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~]|\][^\x07\x1B]*(?:\x07|\x1B\\))"#
```

逐段說明：

| Regex 片段 | 匹配對象 | 例子 |
|-----------|---------|------|
| `\x1B` | ESC 字元本身 | `\x1B` |
| `(?:...)` | Non-capturing group（只用來分組，不捕獲） | — |
| `[@-Z\\-_]` | 2-char escape（Fe sequences）| `\x1B=` `\x1B>` |
| `\[[0-?]*[ -/]*[@-~]` | **CSI sequence**（最常見的類型）| `\x1B[1;32m` `\x1B[2J` |
| `\][^\x07\x1B]*(?:\x07\|\x1B\\)` | **OSC sequence** | `\x1B]0;title\x07` |

CSI sequence 格式分解：`ESC [` + 參數 + 最終字母

```
\x1B [ 1 ; 3 2 m
─┬─ ─┬ ──┬── ─┬
 │   │    │   └ 最終字母（m = 顏色/樣式）
 │   │    └── 參數（1=粗體, 32=綠色）
 │   └── CSI 起始符
 └── ESC
```

### 4.3 `NSRegularExpression` API 詳解

```swift
// ── 建立 regex（只建一次，整個 app 複用）──
// try! 因為 pattern 是硬寫的常數，一定合法
private static let regex: NSRegularExpression = {
    try! NSRegularExpression(
        pattern: pattern,
        options: []          // NSRegularExpression.Options，例如 .caseInsensitive
    )
}()

// ── 使用 regex 替換所有匹配 ──
static func strip(_ input: String) -> String {
    // NSRange 轉換：Swift String.Index → NSRange
    // 寫法固定：NSRange(string.startIndex..., in: string) = 整個字串
    let range = NSRange(input.startIndex..., in: input)

    return regex.stringByReplacingMatches(
        in: input,
        options: [],          // NSRegularExpression.MatchingOptions
        range: range,
        withTemplate: ""      // 替換成空字串 = 刪除所有匹配
    )
}
```

**`NSRange` vs `Range<String.Index>`**：

```swift
// Swift 的 String 用 String.Index（Unicode-safe）
// NSRegularExpression 是 ObjC API，需要 NSRange（byte offset）
// 轉換方式：
let nsRange = NSRange(swiftString.startIndex..., in: swiftString)
//                    ──────────────────────────  ──────────────
//                    closed range from start       在哪個 string 的 context 裡
```

---

## 5. Combine + `@MainActor` 整合

### 5.1 `@Published` 的工作原理

```swift
@MainActor
final class TerminalSession: ObservableObject {

    // @Published 讓這個屬性自動成為 Publisher
    // 每次值改變，訂閱者（TouchBarController）收到通知
    @Published var lastOutputLine: String = ""
    @Published var promptString: String = "% "
}
```

- **`@Published`**：property wrapper，讓屬性帶有 `$lastOutputLine` 這個 `Publisher<String, Never>`
- **`ObservableObject`**：讓整個物件也暴露一個 `objectWillChange` publisher
- **`@MainActor`**：標記這個 class 的所有方法都在 main actor（main thread）執行

### 5.2 Combine `sink` 訂閱

`TouchBarController` 需要在 `TerminalSession` 的屬性改變時更新 UI：

```swift
// 訂閱 session 的 lastOutputLine
// $lastOutputLine：加 $ 前綴取得 Publisher
session.$lastOutputLine
    .receive(on: DispatchQueue.main)   // 確保在 main thread 收到通知
    .sink { [weak self] newLine in
        self?.outputLabel.stringValue = newLine
    }
    .store(in: &cancellables)          // 把 AnyCancellable 存起來，否則立刻取消
```

**為什麼需要 `store(in:)`**：

```swift
// ❌ 錯誤：subscription 沒儲存，立刻被 ARC 釋放，sink 不會被呼叫
session.$lastOutputLine.sink { ... }

// ✅ 正確：存到 cancellables Set，與 controller 生命週期綁定
private var cancellables = Set<AnyCancellable>()
session.$lastOutputLine.sink { ... }.store(in: &cancellables)
```

### 5.3 `Task { @MainActor in ... }` — 切換到 main thread

```swift
// 在 background thread（PTYBridge 的 DispatchSource）收到資料
pty.onOutput = { [weak self] rawText in
    // rawText 在 background thread 到達
    // @Published 屬性必須在 main thread 修改，否則 runtime warning

    // 方法一：Task + @MainActor（現代 Swift Concurrency 寫法）
    Task { @MainActor [weak self] in
        guard let self else { return }
        self.lastOutputLine = AnsiStripper.strip(rawText)
    }

    // 方法二：DispatchQueue.main.async（GCD 舊式寫法，等效）
    DispatchQueue.main.async { [weak self] in
        self?.lastOutputLine = AnsiStripper.strip(rawText)
    }
}
```

---

## 6. Weak Reference — 避免 Retain Cycle

### 6.1 什麼是 Retain Cycle？

```
TerminalSession
  │ 強參考（strong reference）
  ▼
PTYBridge
  │ onOutput closure 強參考
  ▼
TerminalSession  ← 循環！兩個物件互相持有，ARC 永遠不會釋放
```

結果：app 結束後這兩個物件的記憶體都不會被釋放（memory leak）。

### 6.2 用 `[weak self]` 打破循環

```swift
pty.onOutput = { [weak self] rawText in
//               ↑ [weak self]：讓 closure 對 self 使用「弱參考」
//               弱參考不增加 reference count
//               當 TerminalSession 被釋放時，weak self 自動變成 nil

    guard let self else { return }
    //  ↑ self 有可能已被釋放（nil），必須先 guard
    //  Swift 5.3+ 可寫 guard let self（不需要重新命名）

    self.lastOutputLine = AnsiStripper.strip(rawText)
}
```

**什麼時候用 `[weak self]`，什麼時候不用？**

| 情況 | 建議 |
|------|------|
| Closure 捕捉「自己所屬的物件」| 一定用 `[weak self]` |
| Closure 存在比 self 短（例如 URLSession completion） | 可用 `[weak self]`，更安全 |
| Closure 是 escaping 且存活很久 | 一定用 `[weak self]` |
| 非 escaping closure（例如 `map`, `filter`） | 不需要，不會造成 cycle |

---

## 7. 完整資料流圖

```
zsh process
  │ stdout/stderr → slave PTY FD（kernel 自動 echo、行緩衝、signal 轉發）
  ▼
PTY kernel driver
  │
  ▼ master FD 變成 readable
DispatchSource.makeReadSource.setEventHandler
  │ 在 background thread 觸發
  ▼
drain() — Darwin.read(masterFD, &buf, 4096)
  │ 取得 raw bytes
  ▼
String(data: data, encoding: .utf8)   → 原始含 ANSI 的 String
  │
  ▼
onOutput callback（傳給 TerminalSession）
  │
  ▼ Task { @MainActor in }（切回 main thread）
AnsiStripper.strip()              → 移除所有 \x1B[...m 控制碼
AnsiStripper.lastMeaningfulLine() → 取最後一個非空行
  │
  ├─ isPromptLine() == true  → 更新 promptString
  └─ isPromptLine() == false → 更新 lastOutputLine
                                     │
                                     ▼ @Published → Combine publisher 通知
                               TouchBarController.sink
                                     │
                                     ▼
                               NSTextField.stringValue 更新
                                     │
                                     ▼
                               Touch Bar 顯示最新一行輸出
```

---

## 8. 本章新增的檔案結構

```
TouchBarTerminal/
├── App/
│   ├── main.swift
│   └── AppDelegate.swift            （Phase 1，不改）
├── PTY/
│   └── PTYBridge.swift              ← Phase 2 新增
├── Session/
│   ├── AnsiStripper.swift           ← Phase 2 新增
│   └── TerminalSession.swift        （修改：整合 PTYBridge，移除假資料）
└── UI/
    ├── StatusItemController.swift   （Phase 1，不改）
    └── TouchBarController.swift     （Phase 1，不改）
```

---

## 9. 常見錯誤和除錯技巧

| 症狀 | 可能原因 | 解法 |
|------|---------|------|
| Touch Bar 空白，沒有任何輸出 | `forkpty` 失敗 | 印出 `errno`，確認 App Sandbox 關閉 |
| 輸出亂碼（非中文字元） | UTF-8 解碼失敗 | 嘗試 `.isoLatin1` 或 `.ascii` |
| 輸出仍含 `\x1B[...` | AnsiStripper 沒接上 | 確認 `strip()` 在 `onOutput` 裡被呼叫 |
| app crash 於 `stop()` | Double-close FD | 確認 `masterFD = -1` 在 close 之後設定 |
| zsh 沒有出現 prompt | `--login` flag 缺 | `execle` 確認有 `"--login"` 參數 |
| UI 更新在錯誤 thread（警告） | `@Published` 在 background 被寫 | 加 `Task { @MainActor in }` |
| DispatchSource 不觸發 | 忘記呼叫 `resume()` | `source.resume()` 必須呼叫 |
| memory leak | Retain cycle | closure 裡加 `[weak self]` |

---

## 10. 重點整理

| API | 作用 | 關鍵注意事項 |
|-----|------|------------|
| `forkpty(&masterFD, nil, nil, &ws)` | Fork + 建立 PTY pair | 回傳 0 是 child，> 0 是 parent，< 0 是錯誤 |
| `execle(path, arg, ..., nil, environ)` | 替換 child process 成 zsh | varargs 以 `nil` 結尾；`--login` 讓環境完整 |
| `Darwin.read(fd, &buf, count)` | 從 PTY master 讀輸出 | 回傳 ≤ 0 代表 EOF 或錯誤 |
| `Darwin.write(fd, ptr, count)` | 寫使用者輸入到 PTY | 在 serial queue 執行，避免交錯 |
| `Darwin.close(fd)` | 釋放 file descriptor | `stop()` 之後把 `masterFD = -1` |
| `kill(pid, SIGTERM)` | 終止子 process | 先 SIGTERM，再 SIGKILL |
| `DispatchSource.makeReadSource` | 非同步監聽 FD readable | `resume()` 之後才開始；`cancel()` 觸發 cancelHandler |
| `DispatchQueue(label:qos:)` | 建立 serial queue | 用於寫入，保證順序 |
| `DispatchQueue.main.async` | 切回 main thread | 更新 `@Published` 屬性前必須呼叫 |
| `NSRegularExpression` | Regex 匹配和替換 | 靜態建立一次，不要每次呼叫都 new |
| `NSRange(string.startIndex..., in: string)` | Swift String → NSRange | NSRegularExpression 需要 NSRange |
| `[weak self]` in closure | 打破 retain cycle | 搭配 `guard let self else { return }` |
| `Task { @MainActor in }` | 切回 main actor | 等效 `DispatchQueue.main.async`，現代寫法 |
| `.store(in: &cancellables)` | 保存 Combine 訂閱 | 沒 store 訂閱立刻被釋放 |
