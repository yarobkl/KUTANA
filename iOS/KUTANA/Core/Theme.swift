import SwiftUI

enum KutanaTheme {
    static let blue = Color(red: 0.145, green: 0.388, blue: 0.922)
    static let ink = Color(red: 0.04, green: 0.08, blue: 0.18)
    static let canvas = Color(uiColor: .systemBackground)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
}

struct KutanaPrimaryButton: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.headline).frame(maxWidth: .infinity).padding(.vertical, 15)
        }
        .buttonStyle(.borderedProminent)
        .tint(KutanaTheme.blue)
        .controlSize(.large)
    }
}
