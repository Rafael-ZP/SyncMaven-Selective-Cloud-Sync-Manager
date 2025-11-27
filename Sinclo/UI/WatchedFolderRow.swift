internal import SwiftUI

struct WatchedFolderRow: View {
    @ObservedObject var folder: WatchedFolder
    @State private var showDrivePicker = false
    @StateObject private var uploadManager = UploadManager.shared

    var body: some View {
        VStack(alignment: .leading) {
            HStack(spacing: 15) {
                Image(systemName: "folder.fill")
                    .font(.title)
                    .foregroundColor(.accentColor)

                VStack(alignment: .leading, spacing: 5) {
                    Text(folder.localPath.removingPercentEncoding ?? folder.localPath)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    
                    HStack {
                        Image(systemName: "g.circle.fill")
                            .foregroundColor(.gray)
                        Text(folder.driveFolderName ?? "No Drive folder selected")
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    .font(.caption)
                }

                Spacer()

                HStack(spacing: 20) {
                    Button("Rules") {
                        showRulesEditor = true
                    }

                    Button(action: { showDrivePicker = true }) {
                        Image(systemName: "icloud.and.arrow.up")
                        Text("Change")}
                            .onAppear {
                                // Auto-fix invalid accountID
                                if !AccountManager.shared.accounts.contains(where: { $0.id == folder.accountID }) {
                                    folder.accountID = AccountManager.shared.accounts.first?.id ?? ""
                                    AppState.shared.updateFolder(folder)
                                }
                            }

                    Toggle(isOn: $folder.enabled) {
                        Text("")
                    }
                    .toggleStyle(SwitchToggleStyle())
                    .onChange(of: folder.enabled) { _ in
                        AppState.shared.updateFolder(folder)
                    }
                }
            }
            
            let uploads = uploadManager.uploadsForFolder(path: folder.localPath)
            if !uploads.isEmpty {
                Divider().padding(.top, 8)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(uploads) { upload in
                        HStack {
                            Text(upload.localURL.lastPathComponent)
                                .font(.caption)
                            
                            Spacer()
                            
                            switch upload.state {
                            case .pending:
                                Text("Queued")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            case .uploading:
                                ProgressView(value: upload.progress)
                                    .frame(width: 100)
                                    .drawingGroup()
                            case .completed:
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            case .failed:
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.red)
                                Button("Retry") {
                                    uploadManager.retry(recordID: upload.id)
                                }
                                .font(.caption)
                            }
                        }
                    }
                }
                .padding(.top, 8)
            }
        }
        .padding(.vertical, 8)
        .sheet(isPresented: $showDrivePicker) {
            DrivePickerView(
                selectedAccountID: $folder.accountID,
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
        .sheet(isPresented: $showRulesEditor) {
            RulesListView(rules: $folder.rules) {
                AppState.shared.updateFolder(folder)
                showRulesEditor = false
            }
        }
    }
    @State private var showRulesEditor = false
}
