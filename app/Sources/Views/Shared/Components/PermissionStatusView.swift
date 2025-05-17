import SwiftUI

struct PermissionStatusView: View {
    let path: String
    let hasPermission: Bool
    
    var body: some View {
        // HStack(spacing: ViewConstants.secondarySpacing) {
        //     Image(systemName: hasPermission ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
        //         .foregroundColor(hasPermission ? .green : .red)
        //     Text(hasPermission ? "Access Granted" : "Access Required")
        //         .font(.caption)
        //         .foregroundColor(hasPermission ? .secondary : .red)
        // }
        EmptyView()
    }
}


















































