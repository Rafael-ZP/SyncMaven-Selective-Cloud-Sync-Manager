//
//  DrivePickerView.swift
//  Sinclo
//
//  Created by Rafael Zieganpalg on 26/11/25.
//

import Foundation
internal import SwiftUI

struct DrivePickerView: View {
    @StateObject private var accountManager = AccountManager.shared
    
    @Binding var selectedAccountID: String?
    
    // UI State
    @State private var folders: [DriveFolder] = []
    @State private var isLoading = false
    @State private var error: String?
    
    // Selection Binding
    @Binding var selected: DriveFolder?
    
    // Actions
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
    
    // MARK: - Account Selection
    @ViewBuilder private var accountSelectionView: some View {
        VStack {
            Text("Choose a Google Account")
                .font(.title2)
                .bold()
            
            List(accountManager.accounts) { account in
                Button {
                    self.selectedAccountID = account.id
                    loadFolders(for: account.id)
                } label: {
                    HStack(spacing: 10) {
                        if let data = account.avatarData,
                           let image = NSImage(data: data) {
                            Image(nsImage: image)
                                .resizable()
                                .frame(width: 30, height: 30)
                                .clipShape(Circle())
                        } else {
                            Image(systemName: "person.crop.circle.fill")
                                .resizable()
                                .frame(width: 30, height: 30)
                                .foregroundColor(.gray)
                        }
                        
                        Text(account.email)
                            .font(.body)
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
            .listStyle(.inset)
            
            Button("Cancel", action: onCancel)
        }
    }
    
    // MARK: - Folder Selection
    @ViewBuilder private var folderSelectionView: some View {
        VStack {
            Text("Choose a Google Drive Folder")
                .font(.title2)
                .bold()
            
            if isLoading {
                Spacer()
                ProgressView("Fetching folders...")
                Spacer()
            } else if let error = error {
                Spacer()
                Text("Error: \(error)")
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                Button("Retry") {
                    if let id = selectedAccountID { loadFolders(for: id) }
                }
                Spacer()
            } else {
                List(folders, id: \.id) { folder in
                    Button {
                        self.selected = folder
                    } label: {
                        HStack {
                            Image(systemName: selected?.id == folder.id ? "checkmark.circle.fill" : "folder")
                                .foregroundColor(selected?.id == folder.id ? .blue : .gray)
                            Text(folder.name)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.inset)
            }
            
            HStack {
                Button("Back") {
                    withAnimation {
                        selectedAccountID = nil
                        folders = []
                        error = nil
                        selected = nil
                    }
                }
                
                Spacer()
                Button("Cancel", action: onCancel)
                Spacer()
                
                Button("Save", action: onSave)
                    .disabled(selected == nil)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
    
    // MARK: - Logic
    
    private func loadFolders(for accountID: String) {
        isLoading = true
        error = nil
        folders = []
        
        // Explicitly typed closure to help compiler
        GoogleDriveManager.shared.listAllFolders(accountID: accountID) { (result: Result<[DriveFolder], Error>) in
            DispatchQueue.main.async {
                self.isLoading = false
                switch result {
                case .success(let items):
                    self.folders = items.sorted { $0.name < $1.name }
                case .failure(let err):
                    self.error = err.localizedDescription
                }
            }
        }
    }
}
