//
//  WatchedFoldersTab.swift
//  Sinclo
//

import SwiftUI

struct WatchedFoldersTab: View {
    @StateObject private var app = AppState.shared
    @ObservedObject private var uploadManager = UploadManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            HStack {
                Text("Watched Folders")
                    .font(.title2)
                    .bold()

                Spacer()

                Button {
                    app.pickLocalFolder()
                } label: {
                    Label("Add Folder", systemImage: "plus.circle")
                }
            }

            Divider()

            if app.watchedFolders.isEmpty {
                Spacer()
                Text("No folders added yet.")
                    .foregroundColor(.secondary)
                Spacer()
            } else {
                List {
                    ForEach(app.watchedFolders) { folder in
                        WatchedFolderRow(folder: folder)
                    }
                    .onDelete { app.removeFolders(at: $0) }
                }
            }

            Spacer()
        }
    }
}
