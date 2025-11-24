import SwiftUI

struct MainWindow: View {
    @StateObject var app = AppState.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {

            Text("Sinclo Settings")
                .font(.title2)
                .bold()

            Divider()

            HStack {
                Text("Watched Folders")
                    .font(.headline)
                Spacer()
                Button(action: { app.pickLocalFolder() }) {
                    Label("Add Folder", systemImage: "plus.circle")
                }
            }

            List {
                ForEach(app.watchedFolders) { folder in
                    FolderRow(folder: folder)   // <-- THIS IS THE CONNECTION
                }
                .onDelete { idx in app.removeFolders(at: idx) }
            }
            .frame(height: 250)

            Divider()

            VStack(alignment: .leading) {
                Text("Activity Log")
                    .font(.headline)

                ScrollView {
                    ForEach(app.logs, id: \.self) { log in
                        Text(log)
                            .font(.system(size: 11, design: .monospaced))
                    }
                }
                .frame(height: 120)
            }
        }
        .padding(20)
        .frame(width: 600, height: 600)
    }
}
