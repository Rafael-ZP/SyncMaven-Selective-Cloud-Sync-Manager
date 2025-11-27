internal import SwiftUI

struct RuleEditorView: View {
    @Binding var rule: Rule
    
    var body: some View {
        HStack {
            TextField("Min", value: $rule.lowerBound, formatter: NumberFormatter())
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .frame(width: 80)
            
            Text("to")
            
            TextField("Max", value: $rule.upperBound, formatter: NumberFormatter())
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .frame(width: 80)
            
            Picker("", selection: $rule.unit) {
                ForEach(SizeUnit.allCases, id: \.self) { unit in
                    Text(unit.rawValue).tag(unit)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .frame(width: 120)
        }
    }
}
