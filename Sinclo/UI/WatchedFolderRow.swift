//
//  WatchedFolderRow.swift
//  Sinclo
//
//  Created by Rafael Zieganpalg on 26/11/25.
//


//
//  WatchedFolderRow.swift
//

import SwiftUI

struct WatchedFolderRow: View {
    @ObservedObject var folder: WatchedFolder
    @State private var showDrivePicker = false
    @ObservedObject private var uploadManager = UploadManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {

            HStack {
                VStack(alignment: .leading) {
                    Text(folder.localPath)
                        .font(.subheadline)
                        .lineLimit(1)
                    Text("Drive folder: \(folder.driveFolderName ?? "Not chosen")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Toggle("", isOn: $folder.enabled)
                    .toggleStyle(SwitchToggleStyle())
                    .onChange(of: folder.enabled) { _ in
                        AppState.shared.updateFolder(folder)
                    }
            }

            HStack(spacing: 16) {

                VStack(alignment: .leading) {
                    Text("Max size (MB)")
                    TextField("200", value: $folder.maxSizeMB, formatter: NumberFormatter())
                        .frame(width: 80)
                        .onChange(of: folder.maxSizeMB) { _ in
                            AppState.shared.updateFolder(folder)
                        }
                }

                Button(folder.driveFolderName ?? "Choose Drive Folder") {
                    showDrivePicker = true
                }
            }

            // Uploads list
            let uploads = uploadManager.uploadsForFolder(path: folder.localPath)

            if !uploads.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(uploads) { rec in
                        HStack {
                            Text(rec.localURL.lastPathComponent)
                                .font(.system(size: 12))
                                .lineLimit(1)

                            Spacer()

                            switch rec.state {
                            case .uploading:
                                ProgressView(value: rec.progress)
                                    .frame(width: 140)
                            case .pending:
                                Text("Pending").font(.caption)
                            case .completed:
                                Text("Done").font(.caption).foregroundColor(.green)
                            case .failed:
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
        .sheet(isPresented: $showDrivePicker) {
            DrivePickerView(
                selected: Binding(
                    get: { folder.driveFolder },
                    set: {
                        folder.driveFolder = $0
                        folder.driveFolderName = $0?.name
                    }
                ),
                onSave: {
                    AppState.shared.updateFolder(folder)
                    showDrivePicker = false
                },
                onCancel: {
                    showDrivePicker = false
                }
            )
        }
    }
}