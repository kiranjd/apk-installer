import SwiftUI

struct StatusBarView: View {
    @ObservedObject var viewModel: StatusViewModel

    var body: some View {
        // Wrap the conditional view in a Group
        Group {
            // Only render the HStack if the view model is visible
            if viewModel.isVisible {
                HStack(spacing: ViewConstants.secondarySpacing) {
                    // Show ProgressView spinner for .progress type, otherwise show icon
                    if viewModel.statusType == .progress {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 16, height: 16) // Match icon size exactly
                    } else {
                        Image(systemName: iconName)
                            .foregroundColor(iconColor)
                            .font(.system(size: 16, weight: .medium))
                            .frame(width: 16, height: 16) // Ensure consistent icon size
                    }
                    
                    // Message Content
                    Text(viewModel.message)
                        .font(.system(.body, design: .rounded))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .help(viewModel.message)
                    
                    // Optional: Show percentage if progress is available (even with spinner)
                    if viewModel.statusType == .progress, let progress = viewModel.progress {
                        Text(String(format: "(%.0f%%)", progress * 100))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    // Always reserve space for dismiss button to maintain consistent height
                    Group {
                        if viewModel.statusType != .success {
                            Button {
                                viewModel.hide()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary.opacity(0.7))
                            }
                            .buttonStyle(.plain)
                        } else {
                            // Invisible spacer with same size as dismiss button for consistent layout
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.clear)
                        }
                    }
                    .frame(width: 16, height: 16) // Consistent button area size
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity) // Bar spans full width
                .frame(minHeight: 40) // Ensure minimum consistent height
                .background(backgroundMaterial)
                .cornerRadius(8)
                .shadow(color: Color.black.opacity(0.1), radius: 6, x: 0, y: -1)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(borderColor, lineWidth: 0.5)
                        .opacity(0.3)
                )
                // Apply transition to the whole HStack
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        // Animate the appearance/disappearance based on isVisible, applied to the Group
        .animation(.easeOut(duration: 0.3), value: viewModel.isVisible)
    }

    private var iconName: String {
        switch viewModel.statusType {
        case .info: return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .error: return "xmark.octagon.fill"
        // Case for .progress is handled directly in the body now
        case .progress: return "" // Placeholder, not used
        }
    }

    private var iconColor: Color {
        switch viewModel.statusType {
        case .info: return .blue
        case .success: return .green
        case .error: return Color.red.opacity(0.9) // Softer red for dark mode
        // Color for .progress icon is not needed as it's a ProgressView
        case .progress: return .secondary // Placeholder, not used
        }
    }
    
    private var backgroundMaterial: some View {
        Group {
            switch viewModel.statusType {
            case .error:
                Color.red.opacity(0.1)
            case .success:
                Color.green.opacity(0.1)
            case .info, .progress:
                Color.blue.opacity(0.1)
            }
        }
        .background(.thinMaterial)
    }
    
    private var borderColor: Color {
        switch viewModel.statusType {
        case .error: return .red
        case .success: return .green
        case .info, .progress: return .blue
        }
    }
}

#Preview {
    let vm = StatusViewModel()
    // Preview with a progress message shown
    vm.showMessage("Installing APK...", type: .progress, progress: 0.75)
    
    return VStack(spacing: 0) {
        Color.gray.opacity(0.1).ignoresSafeArea()
        Spacer()
        StatusBarView(viewModel: vm)
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
    }
    .frame(width: 600, height: 400)
} 
