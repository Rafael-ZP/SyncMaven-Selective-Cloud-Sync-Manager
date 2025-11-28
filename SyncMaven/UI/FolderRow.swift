internal import SwiftUI

struct FolderRow: View {
    @ObservedObject var folder: WatchedFolder
    @State private var showDrivePicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {

            HStack {
                Text(folder.localPath)
                    .font(.subheadline)
                    .lineLimit(1)

                Spacer()

                Toggle("", isOn: $folder.enabled)
                    .toggleStyle(SwitchToggleStyle())
                    .frame(width: 50)
            }

            HStack(spacing: 16) {

                VStack(alignment: .leading) {
                    Text("Rules")
                    Button("Edit Rules") {
                        showRulesEditor = true
                    }
                }

                VStack(alignment: .leading) {
                    Text("Google Drive Folder")
                    Button(folder.driveFolderName ?? "Choose…") {
                        showDrivePicker = true
                    }
                }
            }
        }
        .padding(6)
        .sheet(isPresented: $showDrivePicker) {
            DrivePickerView(
                selectedAccountID: $folder.accountID,
                selected: Binding(
                    get: { folder.driveFolder },
                    set: { newValue in
                        folder.driveFolder = newValue
                        folder.driveFolderName = newValue?.name
                    }
                ),
                onSave: {
                    // persist changes
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
