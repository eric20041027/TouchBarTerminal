import XCTest
@testable import TouchBarTerminal

/// Touch Bar 右側顯示模式的狀態機（純邏輯）。
///
/// Touch Bar 太窄，終端輸出與 git 按鈕區不能同時顯示，否則 `ls` 這種寬輸出
/// 會把 git 按鈕擠到系統 Control Strip 後面。改成互斥的兩種模式，用左上的
/// git 圖示鈕切換。離開 repo 時強制回 `.output`。
final class GitPanelModeTests: XCTestCase {

    // 預設顯示終端輸出
    func test_default_is_output() {
        XCTAssertEqual(GitPanelMode.output.toggled(), .git)
    }

    // toggle 在 output / git 之間互換
    func test_toggle_switches_between_output_and_git() {
        XCTAssertEqual(GitPanelMode.output.toggled(), .git)
        XCTAssertEqual(GitPanelMode.git.toggled(), .output)
    }

    // 在 repo 內：模式維持不變（toggle 才會動）
    func test_in_repo_keeps_mode() {
        XCTAssertEqual(GitPanelMode.git.afterRepoChange(isRepo: true), .git)
        XCTAssertEqual(GitPanelMode.output.afterRepoChange(isRepo: true), .output)
    }

    // 離開 repo：強制回 output（沒有 git 可顯示）
    func test_leaving_repo_forces_output() {
        XCTAssertEqual(GitPanelMode.git.afterRepoChange(isRepo: false), .output)
        XCTAssertEqual(GitPanelMode.output.afterRepoChange(isRepo: false), .output)
    }
}
