//
//  DrivePickerView.swift
//  Sinclo
//
//  Created by Rafael Zieganpalg on 26/11/25.
//


import SwiftUI

struct DrivePickerView: View {
    @Binding var selected: DriveFolder?
    @State private var folders: [DriveFolder] = []
    @State private var loading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            Text("Choose Google Drive Folder")
                .font(.headline)

            if loading {
                ProgressView("Loading folders…")
                    .padding(.top, 20)
            } else {
                List(folders) { folder in
                    Button(action: {
                        selected = folder
                    }) {
                        HStack {
                            Text(folder.name)
                            Spacer()
                            if selected?.id == folder.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }

            HStack {
                Spacer()
                Button("Close") {
                    NSApp.keyWindow?.close()
                }
            }
            .padding(.top, 8)
        }
        .padding(20)
        .frame(width: 400, height: 500)
        .onAppear {
            loadFolders()
        }
    }

    func loadFolders() {
        GoogleDriveManager.shared.listFolders { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let f):
                    // FIX: convert tuple → model
                    self.folders = f.map { DriveFolder(id: $0.id, name: $0.name) }
                case .failure(let e):
                    print("Error loading folders:", e)
                    self.folders = []
                }
                self.loading = false
            }
        }
    }
}

