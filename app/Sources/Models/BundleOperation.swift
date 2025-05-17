import Foundation

struct BundleOperation: Identifiable {
    let id = UUID()
    let sourcePath: String
    let destPath: String
    let platform: BundlePlatform
}

enum BundlePlatform: String, CaseIterable {
    case ios = "iOS"
    case android = "Android"
    
    var icon: String {
        switch self {
        case .ios: return "iphone.gen3"
        case .android: return "smartphone"
        }
    }
} 