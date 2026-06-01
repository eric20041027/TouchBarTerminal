import Darwin
import Foundation

/// PTY 橋接層
/// 負責 fork 出 zsh、管理 master file descriptor、非同步讀寫
final class PTYBridge {

    /// 有新輸出時呼叫（在 background thread）
    var onOutput: ((String) -> Void)?

    private var masterFD: Int32 = -1
    private var childPID: pid_t = 0
    private var readSource: DispatchSourceRead?

    // serial queue 確保寫入不交錯
    private let writeQueue = DispatchQueue(label: "com.tbt.pty.write", qos: .userInitiated)

    // MARK: - Lifecycle

    func start(shell: String = "/bin/zsh") {
        var ws = winsize(ws_row: 1, ws_col: 80, ws_xpixel: 0, ws_ypixel: 0)
        let pid = forkpty(&masterFD, nil, nil, &ws)

        switch pid {
        case -1:
            // fork 失敗
            print("❌ PTYBridge: forkpty failed, errno=\(errno)")

        case 0:
            // ── child process ──
            // 設定 TERM，讓 zsh 知道自己在終端裡
            setenv("TERM", "xterm-256color", 1)
            // execle 在 Swift 5.9+ unavailable（varargs C 函數），改用 execv
            // argv：程式名稱 + 參數，以 nil 結尾
            let name = (shell as NSString).lastPathComponent
            shell.withCString { shellPtr in
                name.withCString { namePtr in
                    var argv: [UnsafeMutablePointer<CChar>?] = [
                        strdup(namePtr),
                        strdup("--login"),
                        nil
                    ]
                    execv(shellPtr, &argv)
                }
            }
            exit(1)

        default:
            // ── parent process ──
            childPID = pid
            print("✅ PTYBridge: zsh started, pid=\(pid), fd=\(masterFD)")
            startReading()
        }
    }

    func stop() {
        readSource?.cancel()
        readSource = nil

        if childPID > 0 {
            kill(childPID, SIGTERM)
            childPID = 0
        }
        if masterFD >= 0 {
            Darwin.close(masterFD)
            masterFD = -1
        }
    }

    // MARK: - Write

    func writeString(_ string: String) {
        guard let data = string.data(using: .utf8) else { return }
        writeData(data)
    }

    func writeData(_ data: Data) {
        guard masterFD >= 0 else { return }
        // 把 fd 值複製出來，避免 closure 持有 self
        writeQueue.async { [fd = self.masterFD] in
            data.withUnsafeBytes { buf in
                guard let ptr = buf.baseAddress else { return }
                _ = Darwin.write(fd, ptr, data.count)
            }
        }
    }

    // MARK: - Read (private)

    private func startReading() {
        guard masterFD >= 0 else { return }

        let source = DispatchSource.makeReadSource(
            fileDescriptor: masterFD,
            queue: .global(qos: .userInitiated)
        )
        source.setEventHandler { [weak self] in self?.drain() }
        source.setCancelHandler { [fd = masterFD] in Darwin.close(fd) }
        source.resume()
        readSource = source
    }

    private func drain() {
        var buffer = [UInt8](repeating: 0, count: 4096)
        let n = Darwin.read(masterFD, &buffer, buffer.count)
        guard n > 0 else { return }
        guard let str = String(bytes: buffer.prefix(n), encoding: .utf8)
                     ?? String(bytes: buffer.prefix(n), encoding: .isoLatin1) else { return }
        onOutput?(str)
    }
}
