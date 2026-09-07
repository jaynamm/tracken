import Foundation
import CoreServices

/// One recursive OS event stream per directory; a burst of writes triggers one
/// refresh. The owner is the app's store, independent of SwiftUI window tasks.
@MainActor
final class DirectoryChangeMonitor {
    private var stream: FSEventStreamRef?
    private var pending: Task<Void, Never>?
    private var callback: (() -> Void)?

    func start(directory: URL, onChange: @escaping () -> Void) -> Bool {
        stop()
        callback = onChange
        var existingRoot = directory
        while !FileManager.default.fileExists(atPath: existingRoot.path), existingRoot.path != "/" {
            existingRoot.deleteLastPathComponent()
        }
        var context = FSEventStreamContext(version: 0,
                                          info: Unmanaged.passUnretained(self).toOpaque(),
                                          retain: nil, release: nil, copyDescription: nil)
        let handler: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let monitor = Unmanaged<DirectoryChangeMonitor>.fromOpaque(info).takeUnretainedValue()
            Task { @MainActor [weak monitor] in monitor?.scheduleChange() }
        }
        guard let stream = FSEventStreamCreate(nil, handler, &context,
                                               [existingRoot.path] as CFArray,
                                               FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.25,
                                               FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot)) else {
            return false
        }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, .main)
        guard FSEventStreamStart(stream) else { stop(); return false }
        return true
    }

    deinit {
        pending?.cancel()
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }

    func stop() {
        pending?.cancel()
        pending = nil
        callback = nil
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    private func scheduleChange() {
        pending?.cancel()
        pending = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(300)) }
            catch { return }
            self?.callback?()
        }
    }
}
