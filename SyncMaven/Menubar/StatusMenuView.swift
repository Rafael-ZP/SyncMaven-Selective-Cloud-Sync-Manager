internal import SwiftUI

struct StatusMenuView: View {
    @ObservedObject var app = AppState.shared
    @State private var showMainWindow = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {

            Button("Open SyncMaven Settings") {
                openMainWindow()
            }

            Divider()

            Text("Watched Folders:")
                .font(.headline)

            if app.watchedFolders.isEmpty {
                Text("No folders added.")
                    .foregroundColor(.secondary)
                    .padding(.leading, 8)
            } else {
                ForEach(app.watchedFolders) { folder in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(folder.localPath)
                            .font(.system(size: 11))

                        Text("\(folder.rules.count) rules → \(folder.driveFolderName ?? "No Drive Folder")")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }

            Divider()

            Button("Quit SyncMaven") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(12)
        .frame(width: 280)
        
    }

    private func openMainWindow() {
        if let window = NSApp.windows.first(where: { $0.title == "SyncMaven Settings" }) {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let hosting = NSHostingController(rootView: MainWindow())
        let window = NSWindow(
            contentViewController: hosting
        )

        window.title = "SyncMaven Settings"
        window.makeKeyAndOrderFront(nil)
    }
}
