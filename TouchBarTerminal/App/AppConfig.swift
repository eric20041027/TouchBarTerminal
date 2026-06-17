import Foundation

/// 使用者設定，從 ~/.config/touchbarterminal/config.json 載入。
/// 檔案不存在或欄位缺漏時，各欄位回退到預設值。
struct AppConfig: Codable {

    /// 啟動的 shell 路徑
    var shell: String = "/bin/zsh"
    /// Touch Bar 字型大小
    var fontSize: Double = 11
    /// 游標是否閃爍
    var cursorBlink: Bool = true
    /// 右側最多顯示幾行輸出
    var outputLines: Int = 2

    /// 設定檔路徑：~/.config/touchbarterminal/config.json
    static var configURL: URL {
        FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".config/touchbarterminal/config.json")
    }

    /// 載入設定；檔案不存在或解析失敗時回傳預設值。
    static func load() -> AppConfig {
        let url = configURL
        guard let data = try? Data(contentsOf: url) else {
            return AppConfig()   // 沒有設定檔 → 預設值
        }
        do {
            return try JSONDecoder().decode(AppConfig.self, from: data)
        } catch {
            print("⚠️ config.json 解析失敗，使用預設值：\(error)")
            return AppConfig()
        }
    }

    /// 把目前設定寫出成範本（首次執行時方便使用者參考）。
    func writeTemplateIfMissing() {
        let url = Self.configURL
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(self)
            try data.write(to: url)
            print("📝 已建立設定範本：\(url.path)")
        } catch {
            print("⚠️ 無法建立設定範本：\(error)")
        }
    }
}
