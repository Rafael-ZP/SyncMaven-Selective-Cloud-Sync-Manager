// QuickStatusView.swift
// Sinclo
// Modern Popover for Menu Bar

internal import SwiftUI

struct QuickStatusView: View {
    @StateObject var app = AppState.shared
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Sinclo")
                    .font(.headline)
                Spacer()
                Button("Open Settings") {
                    MenuBarController.shared.showMainWindow()
                    MenuBarController.shared.closePopover()
                }
                .buttonStyle(.link)
                .font(.caption)
            }
            .padding(12)
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            // Section 1: Monitored Folders
            VStack(alignment: .leading, spacing: 8) {
                Text("MONITORED FOLDERS")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                
                if app.watchedFolders.isEmpty {
                    Text("No folders configured.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                } else {
                    // FIX: Wrap slice in Array() to help compiler inference
                    ForEach(Array(app.watchedFolders.prefix(3))) { folder in
                        HStack(spacing: 8) {
                            Image(systemName: folder.enabled ? "circle.inset.filled" : "circle")
                                .foregroundColor(folder.enabled ? .green : .gray)
                                .font(.caption2)
                            
                            Text(folder.localPath.lastPathComponent)
                                .font(.system(size: 12))
                                .lineLimit(1)
                            
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                    }
                    
                    if app.watchedFolders.count > 3 {
                        Text("+ \(app.watchedFolders.count - 3) more...")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.leading, 28)
                            .padding(.bottom, 4)
                    }
                }
            }
            
            Divider().padding(.vertical, 4)
            
            // Section 2: Recent Logs
            VStack(alignment: .leading, spacing: 6) {
                Text("RECENT ACTIVITY")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                
                if app.logs.isEmpty {
                    Text("No recent activity.")
                        .font(.caption)
                        .italic()
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 12)
                } else {
                    // FIX: Wrap slice in Array() here too
                    ForEach(Array(app.logs.prefix(5)), id: \.id) { log in
                        Text(log.text)
                            .font(.system(size: 10, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .padding(.horizontal, 12)
                    }
                    .padding(.bottom, 4)
                }
            }
            .padding(.bottom, 12)
        }
        .frame(width: 300)
    }
}

// Extension to get filename easily
extension String {
    var lastPathComponent: String {
        return (self as NSString).lastPathComponent
    }
}
