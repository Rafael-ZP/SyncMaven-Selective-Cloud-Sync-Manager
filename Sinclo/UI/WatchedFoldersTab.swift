// WatchedFoldersTab.swift
// Sinclo
// Modern UI with Card Style

internal import SwiftUI
import Combine

struct WatchedFoldersTab: View {
    @StateObject var app = AppState.shared
    @State private var timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State private var monitoringElapsedTime: String = "0s"

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            
            // --- Header ---
            HStack {
                VStack(alignment: .leading) {
                    Text("Watched Folders")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    Text("Manage sync locations and rules")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: { app.pickLocalFolder() }) {
                    HStack {
                        Image(systemName: "plus")
                        Text("Add Folder")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 10)

            // --- Folder List ---
            ScrollView {
                VStack(spacing: 12) {
                    if app.watchedFolders.isEmpty {
                        emptyStateView
                    } else {
                        ForEach($app.watchedFolders) { $folder in
                            WatchedFolderRow(folder: folder)
                        }
                    }
                }
                .padding(.bottom, 20)
            }
            .frame(maxHeight: .infinity) // Fills space naturally
            
            // --- Footer / Monitor Control ---
            HStack {
                Button(action: {
                    withAnimation { app.toggleMonitoring() }
                }) {
                    HStack {
                        Image(systemName: app.isMonitoring ? "stop.fill" : "play.fill")
                        Text(app.isMonitoring ? "Stop Monitoring" : "Start Monitoring")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(app.isMonitoring ? Color.red.opacity(0.1) : Color.green.opacity(0.1))
                    .foregroundColor(app.isMonitoring ? .red : .green)
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(app.isMonitoring ? Color.red : Color.green, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                
                if app.isMonitoring {
                    VStack(alignment: .trailing) {
                        Text("Active Time")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(monitoringElapsedTime)
                            .font(.title3)
                            .monospacedDigit()
                    }
                    .padding(.leading, 10)
                }
            }
            .padding(.top, 10)
        }
        .padding(24)
        .onReceive(timer) { _ in
            if let startTime = app.monitoringStartTime {
                let interval = Date().timeIntervalSince(startTime)
                let formatter = DateComponentsFormatter()
                formatter.allowedUnits = [.hour, .minute, .second]
                formatter.unitsStyle = .abbreviated
                monitoringElapsedTime = formatter.string(from: interval) ?? "0s"
            }
        }
    }
    
    var emptyStateView: some View {
        VStack(spacing: 15) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 48))
                .foregroundColor(.gray)
            Text("No folders watched")
                .font(.headline)
            Text("Click 'Add Folder' to start syncing.")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.2), lineWidth: 1))
    }
}
