import SwiftUI

struct LocationRow: View {
    let location: APKLocation
    let onDelete: () -> Void
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: ViewConstants.secondarySpacing) {
            HStack(spacing: ViewConstants.secondarySpacing) {
                Image(systemName: "folder.fill")
                    .font(.system(.body, weight: .medium))
                    .foregroundColor(.blue)
                Text(location.path)
                    .font(.body)
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }
            
            Spacer(minLength: ViewConstants.secondarySpacing)
            
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .opacity(isHovered ? 1 : 0)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, ViewConstants.primarySpacing)
        .padding(.vertical, ViewConstants.secondarySpacing)
        .background {
            RoundedRectangle(cornerRadius: ViewConstants.cornerRadius)
                .fill(Color.primary.opacity(ViewConstants.cardBackgroundOpacity))
                .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 1)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }
} 