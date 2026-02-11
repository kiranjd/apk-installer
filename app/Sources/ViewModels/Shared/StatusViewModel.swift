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
    @Published var timestamp: Date? = nil  // When the message was shown
    
    private var autoDismissTask: Task<Void, Never>?
    private var progressCancelAction: (() -> Void)?

    func showMessage(
        _ message: String,
        type: StatusType,
        progress: Double? = nil,
        onCancel: (() -> Void)? = nil
    ) {
        autoDismissTask?.cancel()

        self.message = message
        self.statusType = type
        self.progress = progress
        self.timestamp = Date()
        self.progressCancelAction = (type == .progress) ? onCancel : nil

        if !isVisible {
            self.isVisible = true
        }

        if type != .progress {
            self.progress = nil
        }

        guard type != .progress else { return }
        let dismissDelay: UInt64 = type == .error ? 8_000_000_000 : 4_000_000_000
        autoDismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: dismissDelay)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.hide()
            }
        }
    }
    
    func updateProgress(_ progress: Double) {
        guard statusType == .progress else { return }
        if isVisible {
            self.progress = progress
        }
    }

    func hide() {
        autoDismissTask?.cancel()
        isVisible = false
        progress = nil
        message = ""
        timestamp = nil
        progressCancelAction = nil
    }

    func dismissFromUI() {
        if statusType == .progress {
            progressCancelAction?()
        }
        hide()
    }
    
    deinit {
        autoDismissTask?.cancel()
    }
} 
