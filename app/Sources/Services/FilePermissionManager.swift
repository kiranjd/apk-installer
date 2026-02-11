import Foundation
import os

final class FilePermissionManager {
    static let shared = FilePermissionManager()

    private let userDefaults = UserDefaults.standard
    private let logger = Logger(subsystem: "io.github.apkinstaller.mac", category: "FilePermissionManager")

    private enum Keys {
        static let bookmarks = "security_scoped_bookmarks"
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

        guard let encoded = try? JSONEncoder().encode(bookmarks) else {
            throw NSError(
                domain: "FilePermissionManager",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Unable to persist bookmark for \(url.path)"]
            )
        }

        userDefaults.set(encoded, forKey: Keys.bookmarks)
    }

    func restoreAccess(for path: String) -> Bool {
        guard let bookmarkData = loadBookmarks()[path] else {
            return false
        }

        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            if isStale {
                try saveBookmark(for: URL(fileURLWithPath: path))
            }

            return url.startAccessingSecurityScopedResource()
        } catch {
            logger.error("Bookmark restore failed for \(path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    func removeBookmark(for path: String) {
        var bookmarks = loadBookmarks()
        bookmarks.removeValue(forKey: path)

        guard let encoded = try? JSONEncoder().encode(bookmarks) else {
            return
        }

        userDefaults.set(encoded, forKey: Keys.bookmarks)
    }

    func clearAllBookmarks() {
        userDefaults.removeObject(forKey: Keys.bookmarks)
    }

    func hasBookmark(for path: String) -> Bool {
        loadBookmarks()[path] != nil
    }

    private func loadBookmarks() -> [String: Data] {
        guard let data = userDefaults.data(forKey: Keys.bookmarks),
              let bookmarks = try? JSONDecoder().decode([String: Data].self, from: data) else {
            return [:]
        }
        return bookmarks
    }
}
