// LogsTab.swift
// Sinclo
// Fixed: Removed GeometryReader to prevent AttributeGraph cycles.

internal import SwiftUI
import UniformTypeIdentifiers

struct LogsTab: View {
    @StateObject var app = AppState.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            
            // --- Header Row ---
            HStack(alignment: .center) {
                Text("Activity Log")
                    .font(.title2)
                    .bold()
                
                Spacer()
                
                // Log Retention Picker
                Picker("Keep:", selection: $app.logRetentionLimit) {
                    ForEach(LogRetention.allCases) { limit in
                        Text(limit.displayName).tag(limit)
                    }
                }
                .frame(width: 150)
                .pickerStyle(MenuPickerStyle())
                
                // Download Button
                Button(action: saveLogsToFile) {
                    Image(systemName: "arrow.down.doc")
                    Text("Export")
                }
            }
            .padding(.bottom, 5)

            // --- ScrollView ---
            // Replaced fixed height calculation with flexible frame
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(app.logs, id: \.id) { entry in
                        Text(entry.text)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(.vertical, 2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity) // Fills remaining space naturally
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(6)
        }
        .padding()
    }
    
    func saveLogsToFile() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Sinclo_Logs.txt"
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.plainText]

        if panel.runModal() == .OK, let url = panel.url {
            let text = app.logs.map { $0.text }.joined(separator: "\n")
            do {
                try text.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                print("Failed to save logs:", error)
            }
        }
    }
}
