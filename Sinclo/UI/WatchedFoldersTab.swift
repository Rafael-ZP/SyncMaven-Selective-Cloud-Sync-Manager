//
//  WatchedFoldersTab.swift
//  Sinclo
//
//  Created by Rafael Zieganpalg on 26/11/25.
//


import SwiftUI

struct WatchedFoldersTab: View {
    @EnvironmentObject var app: AppState
    @State private var selectedIndex: Int?

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("Watched Folders").font(.headline)
                Spacer()
                Button(action: { app.pickLocalFolder() }) {
                    Label("Add Folder", systemImage: "plus.circle")
                }
            }

            List {
                ForEach(Array(app.watchedFolders.enumerated()), id: \.element.id) { idx, folder in
                    WatchedFolderRow(folder: folder)
                        .padding(.vertical, 4)
                }
                .onDelete { idxSet in app.removeFolders(at: idxSet) }
            }
            .frame(minHeight: 260)

            HStack {
                Spacer()
                Button("Start Monitoring Now") {
                    SyncManager.shared.startMonitoringAll()
                    app.log("Manual start monitoring triggered")
                }
            }
        }
    }
}
// Replace WatchedFolderRow in WatchedFoldersTab.swift with this code block

struct WatchedFolderRow: View {
    @ObservedObject var folder: WatchedFolder
    @State private var showingPicker = false

    @State private var folderUploads: [UploadRecord] = []
    @ObservedObject private var uploadManager = UploadManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading) {
                    Text(folder.localPath)
                        .font(.subheadline)
                        .lineLimit(1)
                    Text("Drive folder: \(folder.driveFolderName ?? "Not set")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Toggle("Sync", isOn: $folder.enabled)
                    .toggleStyle(SwitchToggleStyle())
                    .labelsHidden()
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading) {
                    Text("Max file size (MB)")
                    TextField("200", value: $folder.maxSizeMB, formatter: NumberFormatter())
                        .frame(width: 80)
                }

                Button(action: { showingPicker = true }) {
                    Label("Choose Drive Folder", systemImage: "folder")
                }

                Spacer()

                Button(action: {
                    // quick scan & enqueue (this will create UploadRecords)
                    let url = URL(fileURLWithPath: folder.localPath)
                    if let items = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) {
                        for item in items {
                            if SyncManager.shared.fileMatchesRule(item, folder: folder) {
                                let parentID = folder.driveFolder?.id
                                UploadManager.shared.startUpload(localURL: item, folderLocalPath: folder.localPath, parentDriveID: parentID)
                            }
                        }
                    }
                }) {
                    Text("Scan & Upload")
                }
            }

            // Upload list for this folder
            if !uploadManager.uploadsForFolder(path: folder.localPath).isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(uploadManager.uploadsForFolder(path: folder.localPath)) { rec in
                        HStack {
                            Text(rec.localURL.lastPathComponent)
                                .lineLimit(1)
                                .font(.system(size: 12))
                            Spacer()
                            if rec.state == .uploading {
                                ProgressView(value: rec.progress)
                                    .frame(width: 140)
                            } else if rec.state == .pending {
                                Text("Queued").font(.caption)
                            } else if rec.state == .completed {
                                Text("Done").font(.caption).foregroundColor(.green)
                            } else {
                                // failed
                                Text("Failed").font(.caption).foregroundColor(.red)
                                Button("Retry") {
                                    UploadManager.shared.retry(recordID: rec.id)
                                }
                            }
                        }
                    }
                }
                .padding(.top, 6)
            }
        }
        .sheet(isPresented: $showingPicker) {
            DrivePickerView(
                selected: Binding(
                    get: { folder.driveFolder },
                    set: { newValue in
                        folder.driveFolder = newValue
                        folder.driveFolderName = newValue?.name
                    }
                ),
                onSave: {
                    AppState.shared.updateFolder(folder)
                    showingPicker = false
                },
                onCancel: {
                    showingPicker = false
                }
            )
        }
    }
}

