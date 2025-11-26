//
//  LogsTab.swift
//  Sinclo
//
//  Created by Rafael Zieganpalg on 26/11/25.
//


import SwiftUI

struct LogsTab: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("Logs").font(.headline)
                Spacer()
                Button("Clear") { app.logs.removeAll() }
                Button("Export") { exportLogs() }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(app.logs, id: \.self) { line in
                        Text(line)
                            .font(.system(size: 11, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }.frame(minHeight: 320)
        }
    }

    func exportLogs() {
        let savePanel = NSSavePanel()
        savePanel.nameFieldStringValue = "sinclo-logs.txt"
        savePanel.begin { resp in
            guard resp == .OK, let url = savePanel.url else { return }
            let text = app.logs.joined(separator: "\n")
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}