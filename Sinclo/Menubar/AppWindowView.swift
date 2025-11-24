//
//  AppWindowView.swift
//  Sinclo
//
//  Created by Rafael Zieganpalg on 26/11/25.
//


import SwiftUI

struct AppWindowView: View {
    @State private var isAuthorizing = false
    @State private var driveFolders: [(id: String, name: String)] = []
    @State private var selectedFolderID: String? = nil
    @State private var newFolderName: String = ""
    @State private var accountEmail: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Sinclo").font(.title2).bold()
                Spacer()
                if OAuth2PKCE.shared.loadTokens() != nil {
                    Button("Disconnect") { disconnect() }
                }
            }

            GroupBox(label: Text("Google Drive")) {
                VStack(alignment: .leading, spacing: 8) {
                    if OAuth2PKCE.shared.loadTokens() == nil {
                        Button(action: {
                            isAuthorizing = true
                            OAuth2PKCE.shared.startAuthorization { res in
                                DispatchQueue.main.async {
                                    isAuthorizing = false
                                    switch res {
                                    case .success(_):
                                        fetchFolders()
                                    case .failure(let e):
                                        print("Auth failed: \(e)")
                                    }
                                }
                            }
                        }, label: {
                            Text(isAuthorizing ? "Authorizing..." : "Connect Google Account")
                        })
                    } else {
                        Text("Account:").font(.subheadline).foregroundColor(.secondary)
                        Text(accountEmail ?? "Signed in").font(.body)
                        Divider()
                        HStack {
                            Button("Refresh Folders") { fetchFolders() }
                            Spacer()
                            Button("Open Drive in Browser") {
                                if let url = URL(string: "https://drive.google.com/drive/my-drive") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                        }
                    }
                }
                .padding(8)
            }

            GroupBox(label: Text("Select/Create Folder")) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Picker(selection: $selectedFolderID, label: Text("Drive folder")) {
                            Text("Choose...").tag(String?.none)
                            ForEach(driveFolders, id: \.id) { f in
                                Text(f.name).tag(Optional(f.id))
                            }
                        }.frame(maxWidth: .infinity)
                        Button("Use") {
                            if let id = selectedFolderID {
                                UserDefaults.standard.set(id, forKey: "Sinclo.GoogleDrive.SelectedFolderID")
                            }
                        }
                    }
                    HStack {
                        TextField("New folder name", text: $newFolderName)
                        Button("Create") {
                            guard !newFolderName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                            GoogleDriveManager.shared.createFolder(named: newFolderName) { res in
                                DispatchQueue.main.async {
                                    switch res {
                                    case .success(let id):
                                        fetchFolders()
                                        selectedFolderID = id
                                        UserDefaults.standard.set(id, forKey: "Sinclo.GoogleDrive.SelectedFolderID")
                                        newFolderName = ""
                                    case .failure(let e):
                                        print("Create folder failed: \(e)")
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(8)
            }

            Spacer()
            HStack {
                Text("Selected Drive folder ID:")
                Text(UserDefaults.standard.string(forKey: "Sinclo.GoogleDrive.SelectedFolderID") ?? "None").font(.caption)
                Spacer()
                Button("Close") {
                    NSApp.keyWindow?.close()
                }
            }
        }
        .padding()
        .frame(width: 520, height: 360)
        .onAppear { fetchFolders(); fetchAccountMail() }
    }

    private func fetchFolders() {
        GoogleDriveManager.shared.listFolders { res in
            DispatchQueue.main.async {
                switch res {
                case .success(let arr): driveFolders = arr
                case .failure(let e): print("List folders failed: \(e)")
                }
            }
        }
    }

    private func fetchAccountMail() {
        // Optional: call Google People API or decode ID token if present.
        // For MVP just show Signed in
        accountEmail = "Signed in"
    }

    private func disconnect() {
        OAuth2PKCE.shared.clearTokens()
        driveFolders = []
        selectedFolderID = nil
        UserDefaults.standard.removeObject(forKey: "Sinclo.GoogleDrive.SelectedFolderID")
    }
}