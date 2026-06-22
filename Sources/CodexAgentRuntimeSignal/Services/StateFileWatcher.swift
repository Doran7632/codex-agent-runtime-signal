import Foundation

final class StateFileWatcher {
    private let directoryURL: URL
    private let onChange: @MainActor @Sendable () -> Void
    private let debounceInterval: TimeInterval
    private let pendingChangeLock = NSLock()
    private var fileDescriptor: CInt = -1
    private var source: DispatchSourceFileSystemObject?
    private var pendingChange: DispatchWorkItem?

    init(
        stateFileURL: URL,
        debounceInterval: TimeInterval = 0.25,
        onChange: @escaping @MainActor @Sendable () -> Void
    ) {
        directoryURL = stateFileURL.deletingLastPathComponent()
        self.debounceInterval = debounceInterval
        self.onChange = onChange
    }

    deinit {
        stop()
    }

    func start() {
        stop()

        try? FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        fileDescriptor = open(directoryURL.path, O_EVTONLY)
        guard fileDescriptor >= 0 else {
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .rename, .delete],
            queue: DispatchQueue.global(qos: .utility)
        )

        source.setEventHandler { [weak self] in
            self?.scheduleChange()
        }

        source.setCancelHandler { [fileDescriptor] in
            if fileDescriptor >= 0 {
                close(fileDescriptor)
            }
        }

        self.source = source
        source.resume()
    }

    func stop() {
        pendingChangeLock.lock()
        pendingChange?.cancel()
        pendingChange = nil
        pendingChangeLock.unlock()

        source?.cancel()
        source = nil
        fileDescriptor = -1
    }

    private func scheduleChange() {
        let onChange = self.onChange
        let workItem = DispatchWorkItem {
            Task { @MainActor in
                onChange()
            }
        }

        pendingChangeLock.lock()
        pendingChange?.cancel()
        pendingChange = workItem
        pendingChangeLock.unlock()

        DispatchQueue.global(qos: .utility).asyncAfter(
            deadline: .now() + debounceInterval,
            execute: workItem
        )
    }
}
