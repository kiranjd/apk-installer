import Foundation

extension FileManager {
    static func getAPKFiles(in directoryURL: URL) -> [APKFile] {
        let fileManager = Foundation.FileManager.default
        
        do {
            let resourceKeys: [URLResourceKey] = [.nameKey, .fileSizeKey, .contentModificationDateKey]
            let enumerator = fileManager.enumerator(
                at: directoryURL,
                includingPropertiesForKeys: resourceKeys,
                options: [.skipsHiddenFiles]
            )
            
            var apkFiles: [APKFile] = []
            
            while let fileURL = enumerator?.nextObject() as? URL {
                guard fileURL.pathExtension.lowercased() == "apk" else { continue }
                
                let resourceValues = try fileURL.resourceValues(forKeys: Set(resourceKeys))
                guard let fileName = resourceValues.name,
                      let fileSize = resourceValues.fileSize,
                      let modDate = resourceValues.contentModificationDate else { continue }
                
                let apkFile = APKFile(
                    name: fileName,
                    path: fileURL.path,
                    size: Int64(fileSize),
                    modificationDate: modDate
                )
                apkFiles.append(apkFile)
            }
            
            return apkFiles.sorted { $0.modificationDate > $1.modificationDate }
        } catch {
            print("⚠️ Error scanning directory: \(error.localizedDescription)")
            return []
        }
    }
}