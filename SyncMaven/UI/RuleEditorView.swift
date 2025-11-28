// RuleEditorView.swift
internal import SwiftUI

struct RuleEditorView: View {
    @Binding var rule: Rule
    var canRemove: Bool
    var onRemove: () -> Void
    
    @State private var newExtension: String = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            
            // Header Row (Rule #)
            HStack {
                Text("Rule Condition")
                    .font(.headline)
                    .foregroundColor(.accentColor)
                Spacer()
                if canRemove {
                    Button(action: onRemove) {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            // Size Range
            HStack(spacing: 12) {
                Text("Sync files between:")
                    .frame(width: 120, alignment: .leading)
                
                TextField("Min", value: $rule.lowerBound, formatter: NumberFormatter())
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(width: 60)
                
                Text("and")
                
                TextField("Max", value: $rule.upperBound, formatter: NumberFormatter())
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(width: 60)
                
                Picker("", selection: $rule.unit) {
                    ForEach(SizeUnit.allCases, id: \.self) { unit in
                        Text(unit.rawValue).tag(unit)
                    }
                }
                .frame(width: 80)
            }
            
            Divider()
            
            // Ignore Extensions
            VStack(alignment: .leading, spacing: 8) {
                Text("Ignore files with extensions:")
                    .font(.subheadline)
                
                HStack {
                    // Input Field
                    TextField("e.g. dmg, iso (Press Enter)", text: $newExtension, onCommit: addExtension)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    
                    // Quick Add Dropdown
                    Menu {
                        ForEach(Rule.commonExtensions, id: \.self) { ext in
                            Button(ext) {
                                if !rule.ignoredExtensions.contains(ext) {
                                    rule.ignoredExtensions.append(ext)
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "list.bullet.circle")
                    }
                    .frame(width: 30)
                }
                
                // Chips View (Tags)
                if !rule.ignoredExtensions.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(rule.ignoredExtensions, id: \.self) { ext in
                                HStack(spacing: 4) {
                                    Text(ext)
                                        .font(.caption)
                                        .fontWeight(.medium)
                                    Button(action: {
                                        rule.ignoredExtensions.removeAll { $0 == ext }
                                    }) {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 8))
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.gray.opacity(0.2))
                                .cornerRadius(12)
                            }
                        }
                    }
                } else {
                    Text("No file types ignored")
                        .font(.caption)
                        .italic()
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.2), lineWidth: 1))
    }
    
    private func addExtension() {
        let clean = newExtension.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !clean.isEmpty && !rule.ignoredExtensions.contains(clean) {
            rule.ignoredExtensions.append(clean)
            newExtension = ""
        }
    }
}
