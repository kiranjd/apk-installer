import Foundation

#if canImport(Dispatch)
import Dispatch
#endif

/// DirectoryMonitor monitors filesystem changes for a directory at a given URL.
final class DirectoryMonitor {
    private let url: URL
    private var descriptor: CInt = -1
    private var source: DispatchSourceFileSystemObject?

    /// Initializes the monitor for the specified directory URL.
    /// - Parameter url: The directory URL to monitor.
    init(url: URL) {
        self.url = url
    }

    deinit {
        stop()
    }

    /// Starts monitoring the directory. The handler is called when changes are observed.
    /// - Parameter handler: Closure invoked on directory change events.
    func start(_ handler: @escaping () -> Void) {
        stop()

        descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else {
            print("⚠️ DirectoryMonitor: Unable to open directory at path \(url.path)")
            return
        }

        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .delete, .extend, .attrib, .link, .rename, .revoke],
            queue: DispatchQueue.global()
        )

        source?.setEventHandler(handler: handler)
        source?.setCancelHandler { [descriptor] in
            close(descriptor)
        }

        source?.resume()
    }

    /// Stops monitoring the directory and releases resources.
    func stop() {
        source?.cancel()
        source = nil
    }
}