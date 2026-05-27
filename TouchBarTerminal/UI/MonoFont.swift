import AppKit

enum MonoFont {
    /// SF Mono 優先，回退 Menlo
    static let `default`: NSFont = {
        NSFont(name: "SFMono-Regular", size: 11)
            ?? NSFont(name: "Menlo-Regular", size: 11)
            ?? NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
    }()
}
