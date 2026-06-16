import Foundation
import Darwin

final class PTYBridge {

    var onOutput: ((String) -> Void)?

    private var masterFD: Int32 = -1
    private var childPID: pid_t = 0
    private var readSource: DispatchSourceRead?
    private let writeQueue = DispatchQueue(label: "com.tbt.pty.write", qos: .userInitiated)

    // MARK: - Lifecycle

    func start(shell: String = "/bin/zsh") {
        var master: Int32 = 0
        var windowSize = winsize(ws_row: 1, ws_col: 200, ws_xpixel: 0, ws_ypixel: 0)

        // fork 前在父行程取得 home path，子行程繼承
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path

        let pid = forkpty(&master, nil, nil, &windowSize)

        if pid < 0 {
            print("❌ forkpty failed")
            return
        }

        if pid == 0 {
            // 子行程：切到 home 再執行 zsh
            setenv("TERM", "dumb", 1)
            setenv("TERM_PROGRAM", "TouchBarTerminal", 1)
            homePath.withCString { _ = chdir($0) }
            var args: [UnsafeMutablePointer<CChar>?] = [strdup(shell), strdup("-l"), nil]
            execv(shell, &args)
            exit(1)
        }

        // 父行程
        self.masterFD = master
        self.childPID = pid
        print("✅ PTY started, pid: \(pid)")
        startReading()
    }

    func stop() {
        readSource?.cancel()
        readSource = nil
        if childPID > 0 { kill(childPID, SIGTERM) }
        if masterFD >= 0 { Darwin.close(masterFD) }
        masterFD = -1
        childPID = 0
    }

    // MARK: - Write

    func writeString(_ string: String) {
        guard let data = string.data(using: .utf8) else { return }
        writeQueue.async { [weak self] in
            guard let self, self.masterFD >= 0 else { return }
            data.withUnsafeBytes { buf in
                guard let ptr = buf.baseAddress else { return }
                _ = Darwin.write(self.masterFD, ptr, data.count)
            }
        }
    }

    // MARK: - Read

    private func startReading() {
        let source = DispatchSource.makeReadSource(
            fileDescriptor: masterFD,
            queue: .global(qos: .userInitiated)
        )
        source.setEventHandler { [weak self] in self?.drain() }
        source.setCancelHandler { [fd = masterFD] in Darwin.close(fd) }
        source.resume()
        self.readSource = source
    }

    private func drain() {
        var buffer = [UInt8](repeating: 0, count: 4096)
        let n = Darwin.read(masterFD, &buffer, buffer.count)
        guard n > 0 else { return }
        let data = Data(buffer.prefix(n))
        guard let str = String(data: data, encoding: .utf8) else { return }
        DispatchQueue.main.async { self.onOutput?(str) }
    }
    func writeData(_ data: Data) {
        guard masterFD >= 0 else { return }
        writeQueue.async { [weak self] in
            guard let self, self.masterFD >= 0 else { return }
            data.withUnsafeBytes { buf in
                guard let ptr = buf.baseAddress else { return }
                _ = Darwin.write(self.masterFD, ptr, data.count)
            }
        }
    }
    
}
