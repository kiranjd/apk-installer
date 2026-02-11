import Foundation

struct APKFile: Identifiable, Equatable {
    var id: String { path }
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
        hasher.combine(path)
    }

    static func == (lhs: APKLocation, rhs: APKLocation) -> Bool {
        lhs.path == rhs.path
    }

    enum CodingKeys: String, CodingKey {
        case id
        case path
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.path = try container.decode(String.self, forKey: .path)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
    }
}
