import Foundation

/// PTY 橋接層（Phase 2 實作）
/// 負責 fork zsh、管理 stdin/stdout file descriptor
final class PTYBridge {

    var onOutput: ((String) -> Void)?

    private var masterFD: Int32 = -1
    private var childPID: pid_t = 0
    private var readSource: DispatchSourceRead?
    private let writeQueue = DispatchQueue(label: "com.tbt.pty.write", qos: .userInitiated)

    // MARK: - Lifecycle

    func start(shell: String = "/bin/zsh") {
        // TODO Phase 2: forkpty implementation
        // var winsize = winsize(ws_row: 1, ws_col: 80, ws_xpixel: 0, ws_ypixel: 0)
        // childPID = forkpty(&masterFD, nil, nil, &winsize)
        // ...
    }

    func stop() {
        readSource?.cancel()
        readSource = nil
        if childPID > 0 { kill(childPID, SIGTERM) }
        if masterFD >= 0 { Darwin.close(masterFD) }
        masterFD = -1
        childPID = 0
    }

    // MARK: - I/O

    func writeString(_ string: String) {
        guard let data = string.data(using: .utf8) else { return }
        writeData(data)
    }

    func writeData(_ data: Data) {
        guard masterFD >= 0 else { return }
        writeQueue.async { [fd = self.masterFD] in
            data.withUnsafeBytes { buf in
                guard let ptr = buf.baseAddress else { return }
                _ = Darwin.write(fd, ptr, data.count)
            }
        }
    }

    // MARK: - Reading (Phase 2)

    private func startReading() {
        guard masterFD >= 0 else { return }
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
}
