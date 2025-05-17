import SwiftUI
import AppKit
import Foundation

struct BundleManagerView: View {
    @StateObject var state: BundleManagerState
    @Binding var selection: Int?
    
    var body: some View {
        VStack(alignment: .leading, spacing: ViewConstants.primarySpacing) {
            // Platform Selection
            HStack {
                Text("Target Platform:")
                    .foregroundColor(.secondary)
                Picker("", selection: $state.selectedPlatform) {
                    ForEach(BundlePlatform.allCases, id: \.self) { platform in
                        Text(platform.rawValue).tag(platform)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
            }
            .padding(.horizontal, ViewConstants.primarySpacing)
            
            // Path Selection Cards with Permission Status
            VStack(spacing: ViewConstants.cardSpacing) {
                VStack(alignment: .leading, spacing: 4) {
                    PathSelectionCard(
                        title: "React Native Source",
                        path: $state.sourcePath,
                        icon: "folder.fill.badge.gearshape",
                        editIcon: "square.and.pencil",
                        onSelect: { selectPath(for: \.sourcePath) },
                        onDisabledTap: nil
                    )
                    if !state.sourcePath.isEmpty {
                        PermissionStatusView(path: state.sourcePath, hasPermission: state.hasSourcePermission)
                            .padding(.leading, ViewConstants.primarySpacing)
                            .transition(.opacity)
                            .animation(.easeInOut, value: state.sourcePath)
                    }
                }
                
                HStack(spacing: ViewConstants.cardSpacing) {
                    // iOS Destination
                    VStack(alignment: .leading, spacing: 4) {
                        PathSelectionCard(
                            title: "iOS Destination",
                            path: $state.iosDestPath,
                            icon: "apple.logo",
                            editIcon: "square.and.pencil",
                            onSelect: { selectPath(for: \.iosDestPath) },
                            onDisabledTap: {
                                withAnimation { state.selectedPlatform = .ios }
                            }
                        )
                        .disabled(state.selectedPlatform != .ios)
                        .opacity(state.selectedPlatform != .ios ? 0.6 : 1)
                        .animation(.easeInOut, value: state.selectedPlatform)
                        
                        if !state.iosDestPath.isEmpty && state.selectedPlatform == .ios {
                            PermissionStatusView(path: state.iosDestPath, hasPermission: state.hasDestPermission)
                                .padding(.leading, ViewConstants.primarySpacing)
                                .transition(.opacity)
                                .animation(.easeInOut, value: state.selectedPlatform)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 80)
                    
                    // Android Destination
                    VStack(alignment: .leading, spacing: 4) {
                        PathSelectionCard(
                            title: "Android Destination",
                            path: $state.androidDestPath,
                            icon: "android.logo",
                            editIcon: "square.and.pencil",
                            onSelect: { selectPath(for: \.androidDestPath) },
                            onDisabledTap: {
                                withAnimation { state.selectedPlatform = .android }
                            }
                        )
                        .disabled(state.selectedPlatform != .android)
                        .opacity(state.selectedPlatform != .android ? 0.6 : 1)
                        .animation(.easeInOut, value: state.selectedPlatform)
                        
                        if !state.androidDestPath.isEmpty && state.selectedPlatform == .android {
                            PermissionStatusView(path: state.androidDestPath, hasPermission: state.hasDestPermission)
                                .padding(.leading, ViewConstants.primarySpacing)
                                .transition(.opacity)
                                .animation(.easeInOut, value: state.selectedPlatform)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 80)
                }
            }
            
            // Bundle Creation Toggle
            Toggle("Create new bundle", isOn: $state.shouldCreateNewBundle)
                .padding(.horizontal, ViewConstants.primarySpacing)
            
            // Action Button
            Button {
                startBundleCopy()
            } label: {
                HStack {
                    if state.isProcessing {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: ViewConstants.iconSize)
                    } else {
                        Image(systemName: "arrow.right.circle.fill")
                            .frame(width: ViewConstants.iconSize)
                    }
                    Text(state.isProcessing ? "Processing..." : (state.shouldCreateNewBundle ? "Create & Copy Bundle" : "Copy Bundle"))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, ViewConstants.secondarySpacing)
            }
            .buttonStyle(.borderedProminent)
            .disabled(
                state.sourcePath.isEmpty || 
                state.isProcessing || 
                !state.hasSourcePermission || 
                !state.hasDestPermission ||
                (state.selectedPlatform == .ios && state.iosDestPath.isEmpty) ||
                (state.selectedPlatform == .android && state.androidDestPath.isEmpty)
            )
            .padding(.horizontal, ViewConstants.primarySpacing)
            
            // Logs Section
            if !state.operationLogs.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Logs")
                                .font(.headline)
                            Spacer()
                            Button {
                                let logs = state.operationLogs.joined(separator: "\n")
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(logs, forType: .string)
                            } label: {
                                Image(systemName: "doc.on.doc")
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(.horizontal, ViewConstants.secondarySpacing)
                        
                        ForEach(state.operationLogs, id: \.self) { log in
                            HStack(alignment: .top, spacing: 8) {
                                Text(log)
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .textSelection(.enabled)
                                Spacer()
                            }
                            .padding(.horizontal, ViewConstants.secondarySpacing)
                            .padding(.vertical, 4)
                        }
                    }
                }
                .background {
                    RoundedRectangle(cornerRadius: ViewConstants.cornerRadius)
                        .fill(Color.primary.opacity(ViewConstants.cardBackgroundOpacity))
                }
                .padding(.horizontal, ViewConstants.primarySpacing)
            }
            
            if let error = state.errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
                    .padding(.horizontal, ViewConstants.primarySpacing)
            }
            
            Spacer()
        }
        .padding(.vertical, ViewConstants.primarySpacing)
        .onChange(of: state.sourcePath) { _ in 
            savePaths()
            checkPermissions()
        }
        .onChange(of: state.iosDestPath) { _ in
            savePaths()
            checkPermissions()
        }
        .onChange(of: state.androidDestPath) { _ in
            savePaths()
            checkPermissions()
        }
        .onAppear {
            checkPermissions()
        }
    }
    
    private func savePaths() {
        StorageManager.saveBundlePaths(
            source: state.sourcePath,
            iosDest: state.iosDestPath,
            androidDest: state.androidDestPath
        )
    }
    
    private func selectPath(for keyPath: WritableKeyPath<BundleManagerState, String>) {
        let openPanel = NSOpenPanel()
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = true
        openPanel.canChooseFiles = false
        openPanel.prompt = "Select Folder"
        
        openPanel.begin { response in
            if response == .OK {
                if let selectedURL = openPanel.url {
                    do {
                        try FilePermissionManager.shared.saveBookmark(for: selectedURL)
                        
                        if keyPath == \BundleManagerState.sourcePath {
                            state.sourcePath = selectedURL.path
                        } else if keyPath == \BundleManagerState.iosDestPath {
                            state.iosDestPath = selectedURL.path
                        } else if keyPath == \BundleManagerState.androidDestPath {
                            state.androidDestPath = selectedURL.path
                        }
                        
                        checkPermissions()
                    } catch {
                        state.errorMessage = "Failed to save folder access: \(error.localizedDescription)"
                    }
                }
            }
        }
    }
    
    private func checkPermissions() {
        if !state.sourcePath.isEmpty {
            state.hasSourcePermission = FilePermissionManager.shared.restoreAccess(for: state.sourcePath)
        }
        
        // Check permissions only for the selected platform
        if state.selectedPlatform == .ios && !state.iosDestPath.isEmpty {
            state.hasDestPermission = FilePermissionManager.shared.restoreAccess(for: state.iosDestPath)
        } else if state.selectedPlatform == .android && !state.androidDestPath.isEmpty {
            state.hasDestPermission = FilePermissionManager.shared.restoreAccess(for: state.androidDestPath)
        }
        
        if !state.sourcePath.isEmpty && !state.hasSourcePermission {
            state.errorMessage = "Please reselect source folder to grant access"
        } else if state.selectedPlatform == .ios && !state.iosDestPath.isEmpty && !state.hasDestPermission {
            state.errorMessage = "Please reselect iOS destination folder to grant access"
        } else if state.selectedPlatform == .android && !state.androidDestPath.isEmpty && !state.hasDestPermission {
            state.errorMessage = "Please reselect Android destination folder to grant access"
        } else {
            state.errorMessage = nil
        }
    }
    
    private func startBundleCopy() {
        state.isProcessing = true
        state.operationLogs.removeAll()
        state.errorMessage = nil
        
        Task {
            await addLog("🚀 Starting bundle copy operation...")
            await addLog("📂 Source: \(state.sourcePath)")
            await addLog("📱 Destination: \(state.selectedPlatform == .ios ? state.iosDestPath : state.androidDestPath)")
            
            do {
                // Check bundle
                try await checkBundle()
                
                // Copy bundle
                await addLog("📝 Copying bundle files...")
                try await copyBundle()
                
                await addLog("✅ Operation completed successfully!")
            } catch {
                await addLog("❌ Error: \(error.localizedDescription)")
                state.errorMessage = error.localizedDescription
            }
            
            state.isProcessing = false
        }
    }
    
    private func addLog(_ message: String) async {
        await MainActor.run {
            state.operationLogs.append(message)
        }
    }
    
    private func checkBundle() async throws {
        let fileManager = Foundation.FileManager.default
        
        if state.shouldCreateNewBundle {
            await addLog("🔄 Creating new bundle...")
            let output = try await ShellCommand.generateBundle(at: state.sourcePath, platform: state.selectedPlatform)
            await addLog("📦 Bundle generated successfully")
        } else {
            let bundleExists = try ShellCommand.checkBundleExists(at: state.sourcePath, platform: state.selectedPlatform)
            if !bundleExists {
                await addLog("⚠️ Bundle not found, generating new bundle...")
                let output = try await ShellCommand.generateBundle(at: state.sourcePath, platform: state.selectedPlatform)
                await addLog("📦 Bundle generated successfully")
            } else if let info = try ShellCommand.getBundleInfo(at: state.sourcePath, platform: state.selectedPlatform) {
                let timeAgo = info.modificationDate.formatted(.relative(presentation: .named))
                let size = ByteCountFormatter.string(fromByteCount: info.size, countStyle: .file)
                await addLog("📦 Found existing bundle (modified \(timeAgo), size: \(size))")
            }
        }
    }
    
    private func copyBundle() async throws {
        guard state.hasSourcePermission && state.hasDestPermission,
              let sourceURL = StorageManager.resolveBookmark(isSource: true),
              let destURL = StorageManager.resolveBookmark(isSource: false) else {
            throw NSError(domain: "BundleError", code: 1, 
                         userInfo: [NSLocalizedDescriptionKey: "Please reselect folders to grant access"])
        }
        
        let fileManager = Foundation.FileManager.default
        
        // Setup paths using the URLs
        let sourceDistDir = sourceURL.appendingPathComponent("dist").path
        let destBundlePath: String
        let assetsPath: String
        
        // Log if source directory doesn't exist
        if !fileManager.fileExists(atPath: sourceDistDir) {
            await addLog("⚠️ Source dist directory not found at: \(sourceDistDir)")
            if let parentContents = try? fileManager.contentsOfDirectory(atPath: sourceURL.path) {
                await addLog("📁 Contents of source directory:")
                for item in parentContents {
                    await addLog("   - \(item)")
                }
            }
        }
        
        switch state.selectedPlatform {
        case .android:
            let sourceReactAppPath = (sourceDistDir as NSString).appendingPathComponent("reactapp")
            destBundlePath = destURL.appendingPathComponent("android/app/src/main/assets/bundle").path
            assetsPath = destURL.appendingPathComponent("android/app/src/main/res").path
            
            // Log if Android paths don't exist
            if !fileManager.fileExists(atPath: sourceReactAppPath) {
                await addLog("⚠️ Source reactapp directory not found at: \(sourceReactAppPath)")
                if let distContents = try? fileManager.contentsOfDirectory(atPath: sourceDistDir) {
                    await addLog("📁 Contents of dist directory:")
                    for item in distContents {
                        await addLog("   - \(item)")
                    }
                }
            }
            
            // Create destination directories
            try fileManager.createDirectory(atPath: destBundlePath, withIntermediateDirectories: true)
            try fileManager.createDirectory(atPath: assetsPath, withIntermediateDirectories: true)
            
            // Android specific code
            let bundleFile = "app.bundle"
            let sourceBundleFile = (sourceReactAppPath as NSString).appendingPathComponent(bundleFile)
            let destBundleFile = (destBundlePath as NSString).appendingPathComponent(bundleFile)
            
            // Remove existing app.bundle if it exists
            if fileManager.fileExists(atPath: destBundleFile) {
                try? fileManager.removeItem(atPath: destBundleFile)
            }
            
            // Try regular copy first
            do {
                try fileManager.copyItem(atPath: sourceBundleFile, toPath: destBundleFile)
            } catch {
                // If regular copy fails, try elevated copy
                try ShellCommand.runElevatedFileOperation(
                    operation: "cp",
                    path: "\(sourceBundleFile) \(destBundleFile)"
                )
            }
            
            await addLog("✓ Copied app.bundle")
            
            // Copy drawables updated using recursive search similar to python glob
            var drawableCount = 0
            if let enumerator = fileManager.enumerator(atPath: sourceReactAppPath) {
                for case let item as String in enumerator {
                    if item.hasPrefix("drawable") {
                        let sourcePath = (sourceReactAppPath as NSString).appendingPathComponent(item)
                        let destFolderName = (item as NSString).lastPathComponent
                        let destPath = (assetsPath as NSString).appendingPathComponent(destFolderName)

                        var isDir: ObjCBool = false
                        if fileManager.fileExists(atPath: sourcePath, isDirectory: &isDir) {
                            if isDir.boolValue {
                                // For directories, create destination folder if needed
                                if !fileManager.fileExists(atPath: destPath) {
                                    try fileManager.createDirectory(atPath: destPath, withIntermediateDirectories: true)
                                }
                                // Copy each item inside the directory
                                let subItems = try fileManager.contentsOfDirectory(atPath: sourcePath)
                                for subItem in subItems {
                                    let sourceSubPath = (sourcePath as NSString).appendingPathComponent(subItem)
                                    let destSubPath = (destPath as NSString).appendingPathComponent(subItem)
                                    if fileManager.fileExists(atPath: destSubPath) {
                                        try fileManager.removeItem(atPath: destSubPath)
                                    }
                                    try fileManager.copyItem(atPath: sourceSubPath, toPath: destSubPath)
                                }
                                drawableCount += 1
                            } else {
                                // For files, simply overwrite
                                if fileManager.fileExists(atPath: destPath) {
                                    try fileManager.removeItem(atPath: destPath)
                                }
                                try fileManager.copyItem(atPath: sourcePath, toPath: destPath)
                                drawableCount += 1
                            }
                        }
                    }
                }
            }
            await addLog("✓ Copied drawables (\(drawableCount) items)")
            
            // Copy Rive assets
            let sourceRiveAssetsPath = (sourceReactAppPath as NSString).appendingPathComponent("riveAssets")
            let rawDir = (assetsPath as NSString).appendingPathComponent("raw")
            
            if fileManager.fileExists(atPath: sourceRiveAssetsPath) {
                try fileManager.createDirectory(atPath: rawDir, withIntermediateDirectories: true)
                
                var riveCount = 0
                if let riveFiles = try? fileManager.contentsOfDirectory(atPath: sourceRiveAssetsPath) {
                    for file in riveFiles where file.hasSuffix(".riv") {
                        let sourcePath = (sourceRiveAssetsPath as NSString).appendingPathComponent(file)
                        let destPath = (rawDir as NSString).appendingPathComponent(file)
                        
                        if fileManager.fileExists(atPath: destPath) {
                            try fileManager.removeItem(atPath: destPath)
                        }
                        try fileManager.copyItem(atPath: sourcePath, toPath: destPath)
                        riveCount += 1
                    }
                }
                await addLog("✓ Copied Rive assets (\(riveCount) files)")
            } else {
                await addLog("ℹ️ No Rive assets found")
            }
            
            // Clean up duplicate PNGs
            var deletedCount = 0
            if let paths = try? Foundation.FileManager.default.contentsOfDirectory(atPath: assetsPath) {
                let webpFiles = Set(paths.filter { $0.hasSuffix(".webp") }.map { ($0 as NSString).deletingPathExtension })
                for path in paths where path.hasSuffix(".png") {
                    let baseName = (path as NSString).deletingPathExtension
                    if webpFiles.contains(baseName) {
                        try fileManager.removeItem(atPath: (assetsPath as NSString).appendingPathComponent(path))
                        deletedCount += 1
                    }
                }
            }
            if deletedCount > 0 {
                await addLog("✓ Cleaned up \(deletedCount) duplicate PNG files")
            }
            
        case .ios:
            await addLog("📦 iOS Bundle Copy")
            
            // Setup iOS paths - using the parent directory of the selected path
            let iosParentPath = state.iosDestPath
            let iosPath = (iosParentPath as NSString).appendingPathComponent("ios")
            let assetsPath = (iosPath as NSString).appendingPathComponent("assets")
            let riveAssetsPath = (iosPath as NSString).appendingPathComponent("RiveAssets")
            let sourceAssetsPath = (sourceDistDir as NSString).appendingPathComponent("assets")
            let sourceRiveAssetsPath = (sourceAssetsPath as NSString).appendingPathComponent("riveAssets")
            let bundleDestPath = (iosPath as NSString).appendingPathComponent("iosrnapp/main.jsbundle")
            let sourceJsBundlePath = (sourceDistDir as NSString).appendingPathComponent("main.jsbundle")
            // Validate iOS project structure
            let xcodeProjectPath = (iosPath as NSString).appendingPathComponent("iosrnapp.xcodeproj")
            if !fileManager.fileExists(atPath: xcodeProjectPath) {
                await addLog("⚠️ Project not found, checking parent directory contents...")
                if let parentContents = try? fileManager.contentsOfDirectory(atPath: iosParentPath) {
                    await addLog("📁 Contents of parent directory:")
                    for item in parentContents {
                        await addLog("   - \(item)")
                    }
                }
                throw NSError(domain: "BundleError", code: 3,
                            userInfo: [NSLocalizedDescriptionKey: "Invalid iOS destination directory. Please select the 'ios-international' directory that contains the 'ios' folder with iosrnapp.xcodeproj"])
            }
            // Check and generate bundle if needed
            if !fileManager.fileExists(atPath: sourceJsBundlePath) {
                await addLog("⚠️ main.jsbundle not found, generating new bundle...")
                let output = try await ShellCommand.generateBundle(at: state.sourcePath, platform: .ios)
                await addLog(output)
                
                // Verify bundle generation with retries
                let maxRetries = 3
                var retryCount = 0
                var bundleExists = false
                
                while retryCount < maxRetries && !bundleExists {
                    try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                    bundleExists = fileManager.fileExists(atPath: sourceJsBundlePath)
                    
                    if !bundleExists {
                        await addLog("Waiting for bundle to be available (attempt \(retryCount + 1)/\(maxRetries))...")
                        retryCount += 1
                    }
                }
                
                if !bundleExists {
                    throw NSError(domain: "BundleError", code: 2, 
                                userInfo: [NSLocalizedDescriptionKey: "Bundle generation succeeded but main.jsbundle not found after \(maxRetries) retries"])
                }
                await addLog("✅ Bundle generated and verified")
            }
            
            // Clean up existing assets
            if fileManager.fileExists(atPath: assetsPath) {
                try fileManager.removeItem(atPath: assetsPath)
                await addLog("🗑️ Removed existing assets directory")
            }
            
            // Create necessary directories
            try fileManager.createDirectory(atPath: assetsPath, withIntermediateDirectories: true)
            await addLog("📁 Created assets directory")
            
            // Copy main assets
            if let assetContents = try? fileManager.contentsOfDirectory(atPath: sourceAssetsPath) {
                for item in assetContents {
                    let sourcePath = (sourceAssetsPath as NSString).appendingPathComponent(item)
                    let destPath = (assetsPath as NSString).appendingPathComponent(item)
                    try fileManager.copyItem(atPath: sourcePath, toPath: destPath)
                }
                await addLog("✓ Copied main assets contents")
            }
            
            // Handle Rive assets if they exist
            if fileManager.fileExists(atPath: sourceRiveAssetsPath) {
                await addLog("🎨 Processing Rive assets...")
                
                // Get Rive files first
                let riveFiles = try fileManager.contentsOfDirectory(atPath: sourceRiveAssetsPath)
                
                do {
                    // Clean up and create RiveAssets directory
                    if fileManager.fileExists(atPath: riveAssetsPath) {
                        try fileManager.removeItem(atPath: riveAssetsPath)
                    }
                    try fileManager.createDirectory(atPath: riveAssetsPath, withIntermediateDirectories: true)
                    
                    // Clean up and create riveAssets in assets directory
                    let riveDestPath = (assetsPath as NSString).appendingPathComponent("riveAssets")
                    if fileManager.fileExists(atPath: riveDestPath) {
                        try fileManager.removeItem(atPath: riveDestPath)
                    }
                    try fileManager.createDirectory(atPath: riveDestPath, withIntermediateDirectories: true)
                    
                    // Copy Rive files to both locations
                    var copiedCount = 0
                    for file in riveFiles {
                        let sourceFile = (sourceRiveAssetsPath as NSString).appendingPathComponent(file)
                        let destFile1 = (riveAssetsPath as NSString).appendingPathComponent(file)
                        let destFile2 = (riveDestPath as NSString).appendingPathComponent(file)
                        
                        try fileManager.copyItem(atPath: sourceFile, toPath: destFile1)
                        try fileManager.copyItem(atPath: sourceFile, toPath: destFile2)
                        copiedCount += 1
                    }
                    await addLog("✓ Copied \(copiedCount) Rive files to both locations")
                } catch {
                    await addLog("⚠️ Error processing Rive files: \(error.localizedDescription)")
                    throw error
                }
                
                // Update Xcode project for Rive files
                let rubyScriptPath = (iosParentPath as NSString).appendingPathComponent("ci-scripts/add_rive_file_groups_to_xcode.rb")
                if fileManager.fileExists(atPath: rubyScriptPath) {
                    try await ShellCommand.execute("LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 ruby '\(rubyScriptPath)' '\(xcodeProjectPath)' '\(riveAssetsPath)'")
                    await addLog("✓ Updated Xcode project with Rive assets")
                } else {
                    await addLog("⚠️ Rive script not found, skipping Xcode project update")
                }
                
                await addLog("✓ Processed \(riveFiles.count) Rive assets")
            }
            
            // Copy main.jsbundle
            if fileManager.fileExists(atPath: bundleDestPath) {
                try fileManager.removeItem(atPath: bundleDestPath)
            }
            try fileManager.copyItem(atPath: sourceJsBundlePath, toPath: bundleDestPath)
            await addLog("✓ Copied main.jsbundle")
            
            await addLog("✨ iOS bundle copy completed successfully")
        }
    }
} 
