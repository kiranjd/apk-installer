import SwiftUI

struct StatusBarView: View {
    @ObservedObject var viewModel: StatusViewModel
    @State private var now: Date = Date()

    var body: some View {
        Group {
            if viewModel.isVisible {
                HStack(alignment: .center, spacing: ViewConstants.secondarySpacing) {
                    if viewModel.statusType == .progress {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 16, height: 16)
                    } else {
                        Image(systemName: iconName)
                            .foregroundColor(iconColor)
                            .font(.system(size: 16, weight: .medium))
                            .frame(width: 16, height: 16)
                    }

                    Text(viewModel.message)
                        .font(.system(.body, design: .rounded))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(viewModel.message)
                        .layoutPriority(1)

                    Spacer()

                    if viewModel.statusType == .progress {
                        if let progress = viewModel.progress {
                            Text(String(format: "%.0f%%", progress * 100))
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                                .fixedSize()
                        }
                    } else if let ts = viewModel.timestamp {
                        Text(RelativeDateTimeFormatter().localizedString(for: ts, relativeTo: now))
                            .font(.system(.caption, design: .rounded))
                            .foregroundColor(.secondary)
                            .fixedSize()
                    }

                    Button {
                        viewModel.dismissFromUI()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                    .frame(width: 16, height: 16)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 42)
                .background(backgroundMaterial)
                .cornerRadius(8)
                .shadow(color: Color.black.opacity(0.1), radius: 6, x: 0, y: -1)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(borderColor, lineWidth: 0.5)
                        .opacity(0.3)
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.3), value: viewModel.isVisible)
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { tick in
            now = tick
        }
    }

    private var iconName: String {
        switch viewModel.statusType {
        case .info: return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .error: return "xmark.octagon.fill"
        case .progress: return ""
        }
    }

    private var iconColor: Color {
        switch viewModel.statusType {
        case .info: return .blue
        case .success: return .green
        case .error: return Color.red.opacity(0.9)
        case .progress: return .secondary
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
