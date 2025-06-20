import SwiftUI
import Combine

enum StatusType {
    case info
    case success
    case error
    case progress
}

@MainActor
class StatusViewModel: ObservableObject {
    @Published var isVisible: Bool = false
    @Published var message: String = ""
    @Published var statusType: StatusType = .info
    @Published var progress: Double? = nil // Optional progress for progress type
    
    private var autoDismissTask: Task<Void, Never>?

    func showMessage(_ message: String, type: StatusType, progress: Double? = nil) {
        // Cancel any existing auto-dismiss task
        autoDismissTask?.cancel()
        
        self.message = message
        self.statusType = type
        self.progress = progress
        
        // Always ensure visibility when showing a new message
        if !isVisible {
             self.isVisible = true
        }
        
        // Reset progress if the new type isn't progress
        if type != .progress {
            self.progress = nil
        }
        
        // Auto-dismiss success messages after 3 seconds
        if type == .success {
            autoDismissTask = Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
                if !Task.isCancelled {
                    hide()
                }
            }
        }
    }
    
    func updateProgress(_ progress: Double) {
        guard statusType == .progress else { return }
        // Only update progress if a progress message is already visible
        if isVisible {
             self.progress = progress
        }
    }

    func hide() {
        autoDismissTask?.cancel()
        isVisible = false
        progress = nil // Reset progress when hiding
        // Clear message on hide to prevent showing stale text briefly on next show
        message = "" 
    }
    
    deinit {
        autoDismissTask?.cancel()
    }
} 