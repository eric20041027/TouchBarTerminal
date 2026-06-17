import Darwin
import Foundation

/// 查詢指定行程的「目前工作目錄」。
///
/// 比解析 shell prompt 可靠：直接問 zsh 子行程真實的 cwd，
/// 用 macOS 的 proc_pidinfo + PROC_PIDVNODEPATHINFO。
enum ProcessCWD {

    /// 回傳 pid 的工作目錄絕對路徑；查不到回 nil。
    static func of(pid: pid_t) -> String? {
        guard pid > 0 else { return nil }
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        let ret = proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size)
        guard ret > 0 else { return nil }
        return withUnsafePointer(to: &info.pvi_cdir.vip_path) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) {
                String(cString: $0)
            }
        }
    }
}
