import SwiftUI

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
                    Text("Max size (MB)")
                    TextField("200", value: $folder.maxSizeMB, formatter: NumberFormatter())
                        .frame(width: 80)
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
            DrivePickerView(selected: $folder.driveFolder)
        }
    }
}
