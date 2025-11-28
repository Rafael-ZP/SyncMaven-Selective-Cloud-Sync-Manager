// WatchedFolderRow.swift
// SyncMaven
// Modern Row Design

internal import SwiftUI

struct WatchedFolderRow: View {
    @ObservedObject var folder: WatchedFolder
    @State private var showDrivePicker = false
    @State private var showRulesEditor = false
    @State private var isHovering = false
    @StateObject private var uploadManager = UploadManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            
            // --- Top Row: Info & Controls ---
            HStack(spacing: 16) {
                // Icon
                ZStack {
                    Circle()
                        .fill(folder.enabled ? Color.accentColor.opacity(0.1) : Color.gray.opacity(0.1))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: "folder.fill")
                        .font(.title3)
                        .foregroundColor(folder.enabled ? .accentColor : .gray)
                }
                
                // Path Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(folder.localPath.removingPercentEncoding ?? folder.localPath)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    
                    HStack(spacing: 4) {
                        Image(systemName: "cloud.fill")
                            .font(.caption2)
                        Text(folder.driveFolderName ?? "Select Drive Folder...")
                            .font(.subheadline)
                    }
                    .foregroundColor(folder.driveFolderName == nil ? .red : .secondary)
                }
                
                Spacer()
                
                // Action Buttons (Visible on Hover or Always if you prefer)
                HStack(spacing: 12) {
                    Button(action: { showRulesEditor = true }) {
                        Label("\(folder.rules.count) Rules", systemImage: "slider.horizontal.3")
                    }
                    .buttonStyle(BorderedButtonStyle())
                    
                    Button(action: {
                        ensureAccountSelected()
                        showDrivePicker = true
                    }) {
                        Label("Target", systemImage: "arrow.triangle.branch")
                    }
                    .buttonStyle(BorderedButtonStyle())
                    
                    Toggle("", isOn: $folder.enabled)
                        .toggleStyle(SwitchToggleStyle(tint: .accentColor))
                }
            }
            .padding(16)
            
            // --- Upload Progress Section ---
            let uploads = uploadManager.uploadsForFolder(path: folder.localPath)
            if !uploads.isEmpty {
                Divider()
                VStack(spacing: 0) {
                    ForEach(uploads) { upload in
                        UploadProgressRow(upload: upload)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                    }
                }
                .background(Color(nsColor: .controlBackgroundColor))
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.15), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.03), radius: 4, x: 0, y: 2)
        .contextMenu {
            Button("Remove Folder", role: .destructive) {
                if let idx = AppState.shared.watchedFolders.firstIndex(where: { $0.id == folder.id }) {
                    AppState.shared.removeFolders(at: IndexSet(integer: idx))
                }
            }
        }
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
                onCancel: { showDrivePicker = false }
            )
        }
        .sheet(isPresented: $showRulesEditor) {
            RulesListView(rules: $folder.rules) {
                AppState.shared.updateFolder(folder)
                showRulesEditor = false
            }
        }
    }
    
    private func ensureAccountSelected() {
        if folder.accountID == nil || folder.accountID!.isEmpty {
             folder.accountID = AccountManager.shared.accounts.first?.id
             AppState.shared.updateFolder(folder)
        }
    }
}

// Helper Subview for Progress
struct UploadProgressRow: View {
    @ObservedObject var upload: UploadRecord
    
    var body: some View {
        HStack {
            Image(systemName: "doc.fill")
                .foregroundColor(.secondary)
            Text(upload.localURL.lastPathComponent)
                .font(.caption)
                .lineLimit(1)
            Spacer()
            
            if upload.state == .uploading {
                ProgressView(value: upload.progress)
                    .progressViewStyle(LinearProgressViewStyle())
                    .frame(width: 80)
            } else if upload.state == .completed {
                Image(systemName: "checkmark").foregroundColor(.green).font(.caption)
            } else if upload.state == .failed {
                Image(systemName: "exclamationmark.triangle").foregroundColor(.red).font(.caption)
            }
        }
    }
}
