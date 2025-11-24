//
//  AppState.swift
//  Sinclo
//
//  Created by Rafael Zieganpalg on 26/11/25.
//

import Combine
import Foundation
import SwiftUI
import AppKit

final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var watchedFolders: [WatchedFolder] = []
    @Published var logs: [String] = []

    private init() {}

    // Add a folder manually
    func pickLocalFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.title = "Choose a Folder to Sync"

        if panel.runModal() == .OK {
            if let url = panel.url {
                let folder = WatchedFolder(path: url.path)
                watchedFolders.append(folder)
                log("Added folder: \(url.path)")
            }
        }
    }

    func removeFolders(at offsets: IndexSet) {
        for i in offsets {
            let f = watchedFolders[i]
            log("Removed folder: \(f.localPath)")
        }
        watchedFolders.remove(atOffsets: offsets)
    }

    func log(_ text: String) {
        DispatchQueue.main.async {
            self.logs.append("[\(self.timestamp())] \(text)")
            if self.logs.count > 200 {
                self.logs.removeFirst(self.logs.count - 200)
            }
        }
    }

    private func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: Date())
    }
}
