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

struct WatchedFolderRow: View {
    @ObservedObject var folder: WatchedFolder
    @State private var showingPicker = false

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
                    // quick upload test: scan immediate files and enqueue
                    let url = URL(fileURLWithPath: folder.localPath)
                    if let items = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) {
                        for item in items {
                            if SyncManager.shared.fileMatchesRule(item, folder: folder) {
                                SyncManager.shared.enqueueUpload(item)
                            }
                        }
                    }
                }) {
                    Text("Scan & Upload")
                }
            }
        }
        .sheet(isPresented: $showingPicker) {
            DrivePickerView(selected: Binding(
                get: { folder.driveFolder },
                set: { new in
                    folder.driveFolder = new
                    folder.driveFolderName = new?.name
                    // persist changes
                    AppState.shared.log("Set Drive folder for \(folder.localPath) → \(new?.name ?? "nil")")
                    Persistence.shared.saveWatchedFolders(AppState.shared.watchedFolders)
                })
            )
        }
    }
}