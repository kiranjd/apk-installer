import AppKit
import CoreGraphics

enum WindowSnapshotExporter {
    enum SnapshotError: Error, LocalizedError {
        case noVisibleWindow
        case couldNotCreateBitmapRep
        case couldNotCaptureWindowImage
        case couldNotEncodePNG

        var errorDescription: String? {
            switch self {
            case .noVisibleWindow:
                return "No visible window to snapshot."
            case .couldNotCreateBitmapRep:
                return "Could not create bitmap representation for snapshot."
            case .couldNotCaptureWindowImage:
                return "Could not capture window image."
            case .couldNotEncodePNG:
                return "Could not encode snapshot as PNG."
            }
        }
    }

    @MainActor
    static func exportMainWindowPNG(to outputURL: URL) throws {
        guard let window = NSApplication.shared.windows.first(where: { $0.isVisible }) else {
            throw SnapshotError.noVisibleWindow
        }
        try exportWindowPNG(window: window, to: outputURL)
    }

    @MainActor
    static func exportWindowPNG(window: NSWindow, to outputURL: URL) throws {
        // NOTE: Any CoreGraphics window capture path requires Screen Recording permission
        // on modern macOS and will return black images if not granted. Use it only when
        // allowed, otherwise fall back to view caching.
        if CGPreflightScreenCaptureAccess(),
           let cgImage = captureWindowCGImage(window),
           isLikelyValidCapture(cgImage) {
            let bitmap = NSBitmapImageRep(cgImage: cgImage)
            if let pngData = bitmap.representation(using: .png, properties: [:]) {
                try FileManager.default.createDirectory(
                    at: outputURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try pngData.write(to: outputURL, options: .atomic)
                return
            }
        }

        // Fallback: cache the view hierarchy (does not require Screen Recording permission).
        guard let view = window.contentView else {
            throw SnapshotError.noVisibleWindow
        }

        if ProcessInfo.processInfo.environment["APKINSTALLER_SNAPSHOT_DEBUG_VIEW_TREE"] == "1" {
            let viewTreeURL = outputURL
                .deletingPathExtension()
                .appendingPathExtension("viewtree.txt")
            let text = describeViewTree(view)
            try? FileManager.default.createDirectory(
                at: viewTreeURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? text.data(using: .utf8)?.write(to: viewTreeURL, options: .atomic)
        }

        // Ensure layout is up-to-date before caching.
        view.wantsLayer = true
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()

        let bounds = view.bounds
        guard let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else {
            throw SnapshotError.couldNotCreateBitmapRep
        }

        // Fill with a sane background in case some subviews don't draw into the rep.
        if let ctx = NSGraphicsContext(bitmapImageRep: rep) {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = ctx
            let cg = ctx.cgContext
            cg.saveGState()
            // cacheDisplay() can leave a restrictive clip behind; always reset.
            cg.resetClip()
            cg.addRect(bounds)
            cg.clip()
            NSColor.windowBackgroundColor.setFill()
            cg.fill(bounds)
            cg.restoreGState()
            NSGraphicsContext.restoreGraphicsState()
        }

        // Prefer cacheDisplay() (captures AppKit-backed controls reliably).
        view.cacheDisplay(in: bounds, to: rep)

        // Some SwiftUI content (and some materials) may not show up via cacheDisplay().
        // If we detect missing regions, "top up" by rendering the layer tree on top.
        let missingSidebar = isLikelyMissingSidebar(rep: rep)
        let missingDetail = isLikelyMissingDetail(rep: rep)
        if (missingSidebar || missingDetail)
            && ProcessInfo.processInfo.environment["APKINSTALLER_SNAPSHOT_DISABLE_LAYER_TOPUP"] != "1" {
            renderLayerTreeIfAvailable(view: view, window: window, rep: rep, bounds: bounds)
        }

        // cacheDisplay() may clear parts of the bitmap rep (leaving transparency) when
        // some subtrees don't render. Ensure we at least have an opaque background.
        fillTransparentPixelsWithWindowBackground(rep: rep, bounds: bounds)

        // Some SwiftUI scroll-based roots render their content in a subview that
        // cacheDisplay() doesn't always pick up from the root. As a best-effort,
        // separately cache a "detail" subview and composite it into the final image.
        if missingDetail && ProcessInfo.processInfo.environment["APKINSTALLER_SNAPSHOT_DISABLE_SUBVIEW_TOPUP"] != "1" {
            overlayLikelyDetailSubview(window: window, rootView: view, rep: rep, bounds: bounds)
            fillTransparentPixelsWithWindowBackground(rep: rep, bounds: bounds)
        }

        guard let pngData = rep.representation(using: .png, properties: [:]) else {
            throw SnapshotError.couldNotEncodePNG
        }

        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try pngData.write(to: outputURL, options: .atomic)
    }

    @MainActor
    private static func captureWindowCGImage(_ window: NSWindow) -> CGImage? {
        let windowID = CGWindowID(window.windowNumber)

        // Capture only the window (no occlusion) at best resolution.
        // boundsIgnoreFraming: omits the window shadow/frame so we only get the content.
        let imageOptions: CGWindowImageOption = [.boundsIgnoreFraming, .bestResolution]

        return CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            windowID,
            imageOptions
        )
    }

    private static func isLikelyValidCapture(_ cgImage: CGImage) -> Bool {
        // Screen-capture-blocked images are typically solid black. Sample a small grid
        // of pixels; if they are all near-black (and opaque), treat as invalid.
        let rep = NSBitmapImageRep(cgImage: cgImage)
        let w = max(1, rep.pixelsWide)
        let h = max(1, rep.pixelsHigh)

        let xs = stride(from: w / 6, through: (w * 5) / 6, by: max(1, w / 6))
        let ys = stride(from: h / 6, through: (h * 5) / 6, by: max(1, h / 6))

        for y in ys {
            for x in xs {
                guard let c = rep.colorAt(x: x, y: y) else { continue }
                let r = c.redComponent
                let g = c.greenComponent
                let b = c.blueComponent
                let a = c.alphaComponent
                let brightness = (r + g + b) / 3.0

                // Any non-trivial luminance implies this is not a solid-black capture.
                if a > 0.2 && brightness > 0.05 {
                    return true
                }
            }
        }
        return false
    }

    private static func describeViewTree(_ view: NSView, depth: Int = 0) -> String {
        var lines: [String] = []
        let indent = String(repeating: "  ", count: depth)

        let cls = String(describing: type(of: view))
        let frame = view.frame.integral
        let bounds = view.bounds.integral
        let isHidden = view.isHidden
        let wantsLayer = view.wantsLayer
        let layerDesc = view.layer.map { String(describing: type(of: $0)) } ?? "nil"
        let alpha = view.alphaValue

        lines.append(
            "\(indent)\(cls) frame=\(frame) bounds=\(bounds) hidden=\(isHidden) alpha=\(String(format: "%.2f", alpha)) wantsLayer=\(wantsLayer) layer=\(layerDesc) subviews=\(view.subviews.count)"
        )

        for sub in view.subviews {
            lines.append(describeViewTree(sub, depth: depth + 1))
        }

        return lines.joined(separator: "\n")
    }

    private static func renderLayerTreeIfAvailable(view: NSView, window: NSWindow, rep: NSBitmapImageRep, bounds: CGRect) {
        guard let layer = view.layer, let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx

        let cg = ctx.cgContext
        cg.saveGState()
        cg.resetClip()
        cg.addRect(bounds)
        cg.clip()

        // NSGraphicsContext(bitmapImageRep:) generally uses point-based coordinates
        // (rep.size), so do not apply backingScaleFactor here.
        if view.isFlipped {
            cg.translateBy(x: 0, y: bounds.height)
            cg.scaleBy(x: 1, y: -1)
        }

        layer.render(in: cg)

        cg.restoreGState()
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func fillTransparentPixelsWithWindowBackground(rep: NSBitmapImageRep, bounds: CGRect) {
        guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx

        let cg = ctx.cgContext
        cg.saveGState()
        cg.resetClip()
        cg.addRect(bounds)
        cg.clip()
        cg.setBlendMode(.destinationOver)
        NSColor.windowBackgroundColor.setFill()
        cg.fill(bounds)
        cg.restoreGState()

        NSGraphicsContext.restoreGraphicsState()
    }

    @MainActor
    private static func overlayLikelyDetailSubview(window: NSWindow, rootView: NSView, rep: NSBitmapImageRep, bounds: CGRect) {
        let candidates = rootView.subviews
            .filter { !$0.isHidden && $0.alphaValue > 0.01 }

        // Heuristic: "detail" is the largest subview that starts to the right of the sidebar.
        let minX = bounds.width * 0.18
        let detailCandidate = candidates
            .filter { $0.frame.minX >= minX && $0.frame.width >= bounds.width * 0.45 }
            .max(by: { ($0.frame.width * $0.frame.height) < ($1.frame.width * $1.frame.height) })

        guard let detailView = detailCandidate else { return }

        detailView.layoutSubtreeIfNeeded()
        detailView.displayIfNeeded()

        // Some SwiftUI ScrollView-backed trees (notably Settings) render their actual
        // content inside a document view that cacheDisplay() on the container misses.
        // Prefer capturing the best "content" descendant, then composite into the root.
        let captureSourceView = bestDetailRenderSubview(in: detailView) ?? detailView

        captureSourceView.layoutSubtreeIfNeeded()
        captureSourceView.displayIfNeeded()

        let captureBounds = captureSourceView.bounds
        guard let detailRep = captureSourceView.bitmapImageRepForCachingDisplay(in: captureBounds) else { return }

        // Provide a consistent background for the detail rep.
        fillTransparentPixelsWithWindowBackground(rep: detailRep, bounds: captureBounds)

        captureSourceView.cacheDisplay(in: captureBounds, to: detailRep)

        if isLikelyMissingDetail(rep: detailRep) || isLikelyMissingSidebar(rep: detailRep) {
            // Try layer render for the subview too.
            renderLayerTreeIfAvailable(view: captureSourceView, window: window, rep: detailRep, bounds: captureBounds)
            fillTransparentPixelsWithWindowBackground(rep: detailRep, bounds: captureBounds)
        }

        guard let cgDetail = detailRep.cgImage, let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx

        let cg = ctx.cgContext
        cg.saveGState()
        cg.resetClip()
        cg.addRect(bounds)
        cg.clip()

        // Match the root view coordinate system.
        if rootView.isFlipped {
            cg.translateBy(x: 0, y: bounds.height)
            cg.scaleBy(x: 1, y: -1)
        }

        let targetRect = captureSourceView.convert(captureBounds, to: rootView).integral
        cg.draw(cgDetail, in: targetRect)

        cg.restoreGState()
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func bestDetailRenderSubview(in detailView: NSView) -> NSView? {
        // Prefer the scroll document/content view over the scroll container/backdrop,
        // because materials/backdrops often don't render into offscreen contexts.
        let all = allDescendants(of: detailView)
            .filter { !$0.isHidden && $0.alphaValue > 0.01 }

        func score(_ view: NSView) -> Double {
            let area = Double(view.bounds.width * view.bounds.height)
            guard area > 4_000 else { return 0 } // ignore tiny helpers/focus rings

            let name = String(describing: type(of: view))
            var multiplier = 1.0

            if name.contains("PlatformGroupContainer") { multiplier *= 6.0 }
            if name.contains("DocumentView") { multiplier *= 4.0 }
            if view is NSClipView { multiplier *= 3.0 }
            if name.contains("Backdrop") || name.contains("Pocket") || name.contains("Mask") { multiplier *= 0.1 }

            // Prefer views that start in the top-left of their own bounds (typical for content roots).
            if view.bounds.origin != .zero { multiplier *= 0.6 }

            return area * multiplier
        }

        return all.max(by: { score($0) < score($1) })
    }

    private static func allDescendants(of root: NSView) -> [NSView] {
        var out: [NSView] = []
        var stack: [NSView] = [root]
        while let v = stack.popLast() {
            out.append(v)
            stack.append(contentsOf: v.subviews)
        }
        return out
    }

    private static func isLikelyMissingSidebar(rep: NSBitmapImageRep) -> Bool {
        // Heuristic: the sidebar always contains bright text/icons. If we don't see any
        // reasonably bright pixels in the left ~28% of the image, cacheDisplay likely
        // missed part of the composition (common with some SwiftUI materials).
        let w = rep.pixelsWide
        let h = rep.pixelsHigh
        guard w > 0, h > 0 else { return true }

        let leftMaxX = max(1, Int(Double(w) * 0.28))
        let sampleGrid = 9
        let brightThreshold: CGFloat = 0.70

        var brightCount = 0
        for yi in 0..<sampleGrid {
            let y = (h * (yi + 1)) / (sampleGrid + 1)
            for xi in 0..<sampleGrid {
                let x = (leftMaxX * (xi + 1)) / (sampleGrid + 1)
                guard let c = rep.colorAt(x: x, y: y) else { continue }
                let brightness = (c.redComponent + c.greenComponent + c.blueComponent) / 3.0
                if c.alphaComponent > 0.2 && brightness > brightThreshold {
                    brightCount += 1
                }
            }
        }

        // If we sampled zero bright pixels in the sidebar region, treat as missing.
        return brightCount == 0
    }

    private static func isLikelyMissingDetail(rep: NSBitmapImageRep) -> Bool {
        // Heuristic: the detail area should contain some bright text. If the right ~60%
        // has no bright pixels above the status bar, assume the view didn't render.
        let w = rep.pixelsWide
        let h = rep.pixelsHigh
        guard w > 0, h > 0 else { return true }

        let minX = Int(Double(w) * 0.35)
        let maxX = w - 1
        let maxY = max(0, h - 140) // exclude bottom status bar / toasts

        let sampleGrid = 11
        let brightThreshold: CGFloat = 0.75

        var brightCount = 0
        for yi in 0..<sampleGrid {
            let y = (maxY * (yi + 1)) / (sampleGrid + 1)
            for xi in 0..<sampleGrid {
                let x = minX + ((maxX - minX) * (xi + 1)) / (sampleGrid + 1)
                guard let c = rep.colorAt(x: x, y: y) else { continue }
                let brightness = (c.redComponent + c.greenComponent + c.blueComponent) / 3.0
                if c.alphaComponent > 0.2 && brightness > brightThreshold {
                    brightCount += 1
                }
            }
        }

        return brightCount == 0
    }
}
