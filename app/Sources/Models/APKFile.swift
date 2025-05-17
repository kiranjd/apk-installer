import Foundation

struct APKFile: Identifiable {
    let id = UUID()
    let name: String
    let path: String
    let size: Int64
    let modificationDate: Date
}

struct APKLocation: Identifiable, Codable, Hashable {
    let id: UUID
    let path: String
    
    init(id: UUID = UUID(), path: String) {
        self.id = id
        self.path = path
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: APKLocation, rhs: APKLocation) -> Bool {
        lhs.id == rhs.id
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case path
    }
} 