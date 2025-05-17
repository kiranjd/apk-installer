import SwiftUI

struct PathSelectionCard: View {
    let title: String
    @Binding var path: String
    let icon: String
    let editIcon: String
    let onSelect: () -> Void
    let onDisabledTap: (() -> Void)?
    @State private var isHovered = false
    @Environment(\.isEnabled) private var isEnabled
    
    var body: some View {
        HStack(spacing: ViewConstants.secondarySpacing) {
            Image(systemName: icon)
                .font(.system(.body, weight: .medium))
                .foregroundColor(.blue)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                if path.isEmpty {
                    Text("Select path")
                        .foregroundStyle(.secondary)
                } else {
                    Text(path)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            Button {
                    onSelect()
            } label: {
                Image(systemName: editIcon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.blue)
                    .padding(4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(path.isEmpty ? 1 : (isHovered ? 1 : 0.6))
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.blue.opacity(isHovered ? 0.1 : 0))
            }
            .animation(.easeInOut(duration: 0.2), value: isHovered)
        }
        .padding(.horizontal, ViewConstants.primarySpacing)
        .padding(.vertical, ViewConstants.secondarySpacing)
        .background {
            RoundedRectangle(cornerRadius: ViewConstants.cornerRadius)
                .fill(Color.primary.opacity(ViewConstants.cardBackgroundOpacity))
        }
        .padding(.horizontal, ViewConstants.primarySpacing)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
        .onTapGesture {
            if !isEnabled, let onDisabledTap = onDisabledTap {
                onDisabledTap()
            }
        }
    }
} 