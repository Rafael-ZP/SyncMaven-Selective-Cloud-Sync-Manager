import Foundation

class FolderMonitor {
    private var stream: FSEventStreamRef?
    private let callback: () -> Void

    init(path: String, callback: @escaping () -> Void) {
        self.callback = callback
        var context = FSEventStreamContext(version: 0, info: UnsafeMutableRawPointer(Unmanaged.passRetained(self).toOpaque()), retain: nil, release: nil, copyDescription: nil)
        
        stream = FSEventStreamCreate(nil, { (_, info, _, _, _, _) in
            let monitor = Unmanaged<FolderMonitor>.fromOpaque(info!).takeUnretainedValue()
            monitor.callback()
        }, &context, [path] as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 1, UInt32(kFSEventStreamCreateFlagFileEvents))
    }

    func start() {
        guard let stream = stream else { return }
        FSEventStreamScheduleWithRunLoop(stream, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        FSEventStreamStart(stream)
    }

    func stop() {
        guard let stream = stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }
    
    deinit { stop() }
}
