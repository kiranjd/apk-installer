import Foundation

class FilePermissionManager {
    static let shared = FilePermissionManager()
    private let userDefaults = UserDefaults.standard
    
    private enum Keys {
        static let bookmarks = "security_scoped_bookmarks"
    }
    
    struct BookmarkData: Codable {
        let url: String
        let bookmarkData: Data
    }
    
    private init() {}
    
    func saveBookmark(for url: URL) throws {
        let bookmarkData = try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        
        var bookmarks = loadBookmarks()
        bookmarks[url.path] = bookmarkData
        
        if let encoded = try? JSONEncoder().encode(bookmarks) {
            userDefaults.set(encoded, forKey: Keys.bookmarks)
        }
    }
    
    func restoreAccess(for path: String) -> Bool {
        guard let bookmarkData = loadBookmarks()[path] else { return false }
        
        do {
            var isStale = false
            let url = try URL(resolvingBookmarkData: bookmarkData,
                            options: .withSecurityScope,
                            relativeTo: nil,
                            bookmarkDataIsStale: &isStale)
            
            if isStale {
                let refreshedURL = URL(fileURLWithPath: path)
                try saveBookmark(for: refreshedURL)
            }
            
            return url.startAccessingSecurityScopedResource()
        } catch {
            print("⚠️ Failed to restore access: \(error)")
            return false
        }
    }
    
    func removeBookmark(for path: String) {
        var bookmarks = loadBookmarks()
        bookmarks.removeValue(forKey: path)
        
        if let encoded = try? JSONEncoder().encode(bookmarks) {
            userDefaults.set(encoded, forKey: Keys.bookmarks)
        }
    }
    
    private func loadBookmarks() -> [String: Data] {
        guard let data = userDefaults.data(forKey: Keys.bookmarks),
              let bookmarks = try? JSONDecoder().decode([String: Data].self, from: data) else {
            return [:]
        }
        return bookmarks
    }
    
    func hasBookmark(for path: String) -> Bool {
        return loadBookmarks()[path] != nil
    }
} 