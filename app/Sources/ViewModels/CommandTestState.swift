import SwiftUI

class CommandTestState: ObservableObject {
    @Published var command: String = ""
    @Published var output: String = ""
    @Published var isRunning = false
} 