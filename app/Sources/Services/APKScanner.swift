import Foundation

enum APKScanner {
    static func scan(in directoryURL: URL) throws -> [APKFile] {
        let fileManager = FileManager.default
        let resourceKeys: [URLResourceKey] = [.nameKey, .fileSizeKey, .contentModificationDateKey, .isRegularFileKey]

        guard let enumerator = fileManager.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: resourceKeys,
            options: [.skipsHiddenFiles]
        ) else {
            throw NSError(
                domain: "APKScanner",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Unable to enumerate files in \(directoryURL.path)"]
            )
        }

        var results: [APKFile] = []

        while let fileURL = enumerator.nextObject() as? URL {
            guard fileURL.pathExtension.lowercased() == "apk" else { continue }
            let values = try fileURL.resourceValues(forKeys: Set(resourceKeys))
            guard values.isRegularFile == true,
                  let name = values.name,
                  let fileSize = values.fileSize,
                  let modified = values.contentModificationDate else {
                continue
            }

            results.append(
                APKFile(
                    name: name,
                    path: fileURL.path,
                    size: Int64(fileSize),
                    modificationDate: modified
                )
            )
        }

        return results.sorted { $0.modificationDate > $1.modificationDate }
    }
}
