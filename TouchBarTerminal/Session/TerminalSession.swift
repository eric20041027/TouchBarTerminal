import Foundation
import Combine

@MainActor
final class TerminalSession: ObservableObject {

    @Published var lastOutputLine: String = ""
    @Published var inputBuffer: String = ""
    @Published var promptString: String = "% "
    @Published var isConnected: Bool = false

    func start() {
        isConnected = true
        lastOutputLine = "/Users/smallfire"
    }

    func stop() {
        isConnected = false
    }
}
