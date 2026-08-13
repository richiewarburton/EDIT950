import AppKit
import SwiftUI

struct SuiteTableCell<Content: View>: View {
    let selected: Bool
    let alignment: Alignment
    @ViewBuilder let content: () -> Content

    init(
        selected: Bool,
        alignment: Alignment = .center,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.selected = selected
        self.alignment = alignment
        self.content = content
    }

    var body: some View {
        content()
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: alignment
            )
            .foregroundStyle(selected ? Color.suiteOnYellow : Color.primary)
            .tint(selected ? Color.suiteOnYellow : Color.suiteYellow)
    }
}
