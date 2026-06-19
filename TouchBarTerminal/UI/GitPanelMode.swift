import Foundation

/// Touch Bar 右側的顯示模式。
///
/// Touch Bar 寬度有限（與系統 Control Strip 並存後更窄），終端輸出與 git 按鈕區
/// 無法同時完整顯示。改成互斥的兩種模式，由左上的 git 圖示鈕切換。
enum GitPanelMode {
    /// 顯示終端輸出（預設）
    case output
    /// 顯示 git 按鈕區（status / add / commit / push）
    case git

    /// 切換到另一個模式（給 git 圖示鈕用）。
    func toggled() -> GitPanelMode {
        self == .output ? .git : .output
    }

    /// repo 狀態改變後應處於的模式。
    /// 離開 repo（`isRepo == false`）時沒有 git 可顯示，強制回 `.output`；
    /// 仍在 repo 內則維持原模式。
    func afterRepoChange(isRepo: Bool) -> GitPanelMode {
        isRepo ? self : .output
    }
}
