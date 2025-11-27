//
//  DrivePickerView.swift
//  Sinclo
//
//  Created by Rafael Zieganpalg on 26/11/25.
//


internal import SwiftUI

struct DrivePickerView: View {
    @StateObject private var accountManager = AccountManager.shared
    @Binding var selectedAccountID: String?
    
    @State private var folders: [DriveFolder] = []
    @State private var isLoading = false
    @State private var error: String?

    @Binding var selected: DriveFolder?
    var onSave: () -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            if selectedAccountID == nil {
                accountSelectionView
            } else {
                folderSelectionView
            }
        }
        .padding(20)
        .frame(width: 400, height: 500)
        .onAppear {
            if let accountID = selectedAccountID {
                loadFolders(for: accountID)
            }
        }
    }

    @ViewBuilder
    private var accountSelectionView: some View {
        VStack {
            Text("Choose a Google Account")
                .font(.title2)
            List(accountManager.accounts) { account in
                Button(action: {
                    self.selectedAccountID = account.id
                    loadFolders(for: account.id)
                }) {
                    HStack {
                        if let data = account.avatarData, let image = NSImage(data: data) {
                            Image(nsImage: image)
                                .resizable()
                                .frame(width: 30, height: 30)
                                .clipShape(Circle())
                        } else {
                            Image(systemName: "person.crop.circle.fill")
                                .resizable()
                                .frame(width: 30, height: 30)
                        }
                        Text(account.email)
                    }
                }
                .buttonStyle(PlainButtonStyle())
            }
            .listStyle(InsetListStyle())
            
            Button("Cancel", action: onCancel)
        }
    }

    @ViewBuilder
    private var folderSelectionView: some View {
        VStack {
            Text("Choose a Google Drive Folder")
                .font(.title2)

            if isLoading {
                ProgressView()
            } else if let error = error {
                Text("Error: \(error)")
                    .foregroundColor(.red)
            } else {
                List(folders, id: \.id) { folder in
                    Button(action: {
                        self.selected = folder
                    }) {
                        HStack {
                            Image(systemName: self.selected?.id == folder.id ? "checkmark.circle.fill" : "circle")
                            Text(folder.name)
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .listStyle(InsetListStyle())
            }

            HStack {
                Button("Back") {
                    self.selectedAccountID = nil
                    self.folders = []
                    self.error = nil
                }
                Spacer()
                Button("Cancel", action: onCancel)
                Spacer()
                Button("Save", action: onSave)
                    .disabled(selected == nil)
            }
        }
    }

    private func loadFolders(for accountID: String) {
        self.isLoading = true
        self.error = nil
        
        GoogleDriveManager.shared.listFolders(accountID: accountID) { result in
            let workItem = DispatchWorkItem {
                self.isLoading = false
                switch result {
                case .success(let folderList):
                    self.folders = folderList.map { DriveFolder(id: $0.id, name: $0.name) }
                case .failure(let error):
                    self.error = error.localizedDescription
                }
            }
            DispatchQueue.main.async(execute: workItem)
        }
    }
}

