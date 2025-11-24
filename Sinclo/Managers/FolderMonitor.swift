import Foundation

class FolderMonitor {
    private var stream: FSEventStreamRef?
    private let callback: () -> Void

    init(path: String, callback: @escaping () -> Void) {
        self.callback = callback

        var context = FSEventStreamContext(
            version: 0,
            info: UnsafeMutableRawPointer(Unmanaged.passRetained(self).toOpaque()),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        stream = FSEventStreamCreate(
            nil,
            { (_, info, _, _, _, _) in
                let monitor = Unmanaged<FolderMonitor>.fromOpaque(info!).takeUnretainedValue()
                monitor.callback()
            },
            &context,
            [path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1,
            UInt32(kFSEventStreamCreateFlagFileEvents)
        )
    }

    func start() {
        if let s = stream {
            FSEventStreamScheduleWithRunLoop(s, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            FSEventStreamStart(s)
        }
    }

    func stop() {
        if let s = stream {
            FSEventStreamStop(s)
            FSEventStreamInvalidate(s)
            FSEventStreamRelease(s)
        }
    }

    deinit { stop() }
}//
//  FolderMonitor.swift
//  Sinclo
//
//  Created by Rafael Zieganpalg on 26/11/25.
//

