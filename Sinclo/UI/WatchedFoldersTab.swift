internal import SwiftUI
import Combine

struct WatchedFoldersTab: View {
    @StateObject var app = AppState.shared
    @State private var timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State private var monitoringElapsedTime: String = ""

    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Watched Folders")
                        .font(.title2)
                        .bold()
                    Spacer()
                    Button(action: { app.pickLocalFolder() }) {
                        Label("Add Folder", systemImage: "plus.circle")
                    }
                }
                .padding(.bottom, 10)

                List {
                    ForEach(app.watchedFolders) { folder in
                        WatchedFolderRow(folder: folder)
                            .padding(.vertical, 8)
                    }
                    .onDelete { idx in app.removeFolders(at: idx) }
                }
                .listStyle(InsetListStyle())
                .frame(height: geometry.size.height * 0.7)

                HStack {
                    Button(action: {
                        app.toggleMonitoring()
                    }) {
                        Text(app.isMonitoring ? "Stop Monitoring" : "Start Monitoring")
                    }
                    
                    Spacer()
                    
                    if app.isMonitoring {
                        Text("Monitoring for \(monitoringElapsedTime)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.top, 10)
            }
            .padding()
        }
        .onReceive(timer) { _ in
            if let startTime = app.monitoringStartTime {
                let interval = Date().timeIntervalSince(startTime)
                let formatter = DateComponentsFormatter()
                formatter.allowedUnits = [.hour, .minute, .second]
                formatter.unitsStyle = .abbreviated
                let newElapsedTime = formatter.string(from: interval) ?? ""
                if newElapsedTime != monitoringElapsedTime {
                    monitoringElapsedTime = newElapsedTime
                }
            }
        }
    }
}
