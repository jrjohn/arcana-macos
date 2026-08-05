//
//  DecimalField.swift
//  ArcanaShell — a small reusable text field bound to a `Decimal`, shared by the feature
//  editors (orders / products / customers).
//

import SwiftUI

struct DecimalField: View {
    let title: String
    @Binding var value: Decimal
    var width: CGFloat? = nil
    var onChange: () -> Void = {}

    var body: some View {
        TextField(title, text: Binding(
            get: { NSDecimalNumber(decimal: value).stringValue },
            set: { value = Decimal(string: $0) ?? value; onChange() }))
            .frame(width: width)
            .multilineTextAlignment(width == nil ? .leading : .trailing)
    }
}
