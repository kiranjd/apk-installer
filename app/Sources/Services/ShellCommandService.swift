import Foundation

enum ShellCommand {
    static func execute(_ command: String) async throws -> String {
        print("📝 Executing command: \(command)")
        
        let process = Process()
        let pipe = Pipe()
        
        var env = ProcessInfo.processInfo.environment
        let androidHome = env["ANDROID_HOME"] ?? "\(NSHomeDirectory())/Library/Android/sdk"
        let paths = [
            "/usr/local/bin",
            "/opt/homebrew/bin",
            "/usr/bin",
            "\(androidHome)/platform-tools",
            "\(androidHome)/tools",
            "\(androidHome)/tools/bin",
            env["PATH"] ?? ""
        ].joined(separator: ":")
        env["PATH"] = paths
        env["ANDROID_HOME"] = androidHome
        process.environment = env
        
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", "source ~/.zshrc 2>/dev/null || source ~/.bash_profile 2>/dev/null; \(command)"]
        
        process.standardOutput = pipe
        process.standardError = pipe
        
        try process.run()
        process.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        
        print("📝 Command output:\n\(output)")
        
        if process.terminationStatus != 0 {
            throw NSError(domain: "ShellCommand", code: Int(process.terminationStatus),
                         userInfo: [NSLocalizedDescriptionKey: output])
        }
        
        return output
    }
    
    static func uninstallApp(identifier: String, device: String? = nil) async throws -> String {
        let deviceOption = device.map { "-s \($0)" } ?? ""
        let command = ["adb", deviceOption, "uninstall", identifier]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return try await execute(command)
    }
    
    /// Extracts the package identifier from an APK using `aapt dump badging`.
    public static func getPackageIdentifier(from apkPath: String) async throws -> String {
        // Attempt to locate 'aapt' in Android SDK build-tools or rely on PATH
        let env = ProcessInfo.processInfo.environment
        let androidHome = env["ANDROID_HOME"] ?? "\(NSHomeDirectory())/Library/Android/sdk"
        let buildToolsDir = URL(fileURLWithPath: androidHome).appendingPathComponent("build-tools")
        var aaptPath: String = "aapt"
        if let versions = try? FileManager.default.contentsOfDirectory(atPath: buildToolsDir.path).sorted(by: >),
           let latest = versions.first {
            let candidate = buildToolsDir.appendingPathComponent(latest).appendingPathComponent("aapt").path
            if FileManager.default.isExecutableFile(atPath: candidate) {
                aaptPath = candidate
            }
        }
        let output = try await execute("\(aaptPath) dump badging '\(apkPath)'")
        // Look for the package name in the badging output
        for line in output.split(separator: "\n") {
            if line.hasPrefix("package:") {
                let components = line.components(separatedBy: " ")
                for token in components {
                    if token.hasPrefix("name=") {
                        let namePart = token.replacingOccurrences(of: "name=", with: "")
                        return namePart.trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
                    }
                }
            }
        }
        throw NSError(domain: "ShellCommand", code: 0,
                      userInfo: [NSLocalizedDescriptionKey: "Failed to parse package identifier from APK badge"])    
    }
    
    /// Installs (or updates) an APK on the connected device.
    /// - Parameters:
    ///   - path: Filesystem path to the APK to install.
    ///   - isUpdate: If true, perform an update (`-r` flag), otherwise uninstall previous then install.
    ///   - device: Optional device identifier to target with `-s`.
    static func installAPK(path: String, isUpdate: Bool = false, device: String? = nil) async throws -> String {
        var flags = ["-t"]
        if isUpdate {
            flags.append("-r")
        } else {
            // Uninstall any existing app by extracting its package ID from the APK
            let pkgId: String
            do {
                pkgId = try await getPackageIdentifier(from: path)
            } catch {
                // Fallback to manual configured identifier
                pkgId = StorageManager.loadAppIdentifier()
            }
            _ = try? await uninstallApp(identifier: pkgId, device: device)
        }

        let flagsStr = flags.joined(separator: " ")
        let deviceOption = device.map { "-s \($0)" } ?? ""
        // Build command parts, filtering out any empty segments
        let cmd = ["adb", deviceOption, "install", flagsStr, "'\(path)'" ]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return try await execute(cmd)
    }
    
    static func checkBundleExists(at path: String, platform: BundlePlatform) throws -> Bool {
        let fileManager = Foundation.FileManager.default
        switch platform {
        case .ios:
            let bundlePath = (path as NSString).appendingPathComponent("dist/main.jsbundle")
            return fileManager.fileExists(atPath: bundlePath)
        case .android:
            let bundlePath = (path as NSString).appendingPathComponent("dist/reactapp/app.bundle")
            return fileManager.fileExists(atPath: bundlePath)
        }
    }
    
    static func getBundleInfo(at path: String, platform: BundlePlatform) throws -> (modificationDate: Date, size: Int64)? {
        let bundlePath: String
        switch platform {
        case .ios:
            bundlePath = (path as NSString).appendingPathComponent("dist/main.jsbundle")
        case .android:
            bundlePath = (path as NSString).appendingPathComponent("dist/reactapp/app.bundle")
        }
        
        guard let attrs = try? Foundation.FileManager.default.attributesOfItem(atPath: bundlePath) else {
            return nil
        }
        return (
            attrs[.modificationDate] as? Date ?? Date(),
            attrs[.size] as? Int64 ?? 0
        )
    }
    
    static func generateBundle(at path: String, platform: BundlePlatform) async throws -> String {
        let command = platform == .android ? "build-android-local" : "build-ios-local"
        let process = Process()
        let pipe = Pipe()
        
        process.currentDirectoryURL = URL(fileURLWithPath: path)
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        
        var env = ProcessInfo.processInfo.environment
        let paths = [
            "/usr/local/bin",
            "/opt/homebrew/bin",
            "/usr/bin",
            "\(NSHomeDirectory())/.nvm/versions/node/\(env["NODE_VERSION"] ?? "")/bin",
            "\(NSHomeDirectory())/.yarn/bin",
            env["PATH"] ?? ""
        ].joined(separator: ":")
        env["PATH"] = paths
        process.environment = env
        
        process.arguments = ["-c", "source ~/.zshrc 2>/dev/null || source ~/.bash_profile 2>/dev/null; cd '\(path)' && yarn \(command)"]
        
        process.standardOutput = pipe
        process.standardError = pipe
        
        try process.run()
        process.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        
        if process.terminationStatus != 0 {
            throw NSError(domain: "BundleError", code: Int(process.terminationStatus),
                         userInfo: [NSLocalizedDescriptionKey: "Bundle generation failed: \(output)"])
        }
        
        return output
    }
    
    static func runElevatedFileOperation(operation: String, path: String) throws -> String {
        let script = """
            do shell script "\(operation) '\(path)'" with administrator privileges
        """
        
        var error: NSDictionary?
        guard let scriptObject = NSAppleScript(source: script),
              let output = scriptObject.executeAndReturnError(&error).stringValue else {
            if let error = error {
                throw NSError(domain: "ScriptError", code: 1, 
                             userInfo: [NSLocalizedDescriptionKey: error["NSAppleScriptErrorMessage"] as? String ?? "Unknown error"])
            }
            throw NSError(domain: "ScriptError", code: 1, 
                         userInfo: [NSLocalizedDescriptionKey: "Failed to execute script"])
        }
        return output
    }
} 