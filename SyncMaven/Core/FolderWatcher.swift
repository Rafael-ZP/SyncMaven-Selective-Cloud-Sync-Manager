import Foundation

final class FolderWatcher {
    private let folderURL: URL
    private var fileDescriptor: CInt = -1
    private var source: DispatchSourceFileSystemObject?
    private let debounceInterval: TimeInterval = 0.6
    private var lastEvent: Date = Date.distantPast
    private let queue = DispatchQueue(label: "com.SyncMaven.folderwatcher", qos: .utility)
    var onChange: (() -> Void)?

    init(folderURL: URL) {
        self.folderURL = folderURL
    }

    deinit {
        stop()
    }

    func start() throws {
        stop()
        fileDescriptor = open(folderURL.path, O_EVTONLY)
        guard fileDescriptor >= 0 else { throw NSError(domain: "FolderWatcher", code: 1) }

        source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fileDescriptor, eventMask: .write, queue: queue)
        source?.setEventHandler(handler: { [weak self] in
            guard let self = self else { return }
            let now = Date()
            if now.timeIntervalSince(self.lastEvent) > self.debounceInterval {
                self.lastEvent = now
                DispatchQueue.global(qos: .utility).async {
                    self.onChange?()
                }
            }
        })
        source?.setCancelHandler { [fd = fileDescriptor] in
            close(fd)
        }
        source?.resume()
    }

    func stop() {
        source?.cancel()
        source = nil
    }
}
