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
                            .frame(width: 16, height: 16) // Match icon size roughly
                    } else {
                        Image(systemName: iconName)
                            .foregroundColor(iconColor)
                            .font(.system(size: 16, weight: .medium))
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

                    Button {
                        viewModel.hide()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, ViewConstants.primarySpacing)
                .padding(.vertical, ViewConstants.secondarySpacing)
                .frame(maxWidth: .infinity) // Bar spans full width
                .frame(height: 40) // Give the bar a fixed height
                .background(.thinMaterial) // Background material
                .overlay(Divider(), alignment: .top) // Optional top border
                // Apply transition to the whole HStack
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        // Animate the appearance/disappearance based on isVisible, applied to the Group
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: viewModel.isVisible)
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
        case .error: return .red
        // Color for .progress icon is not needed as it's a ProgressView
        case .progress: return .secondary // Placeholder, not used
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
    }
    .frame(width: 600, height: 400)
} 
