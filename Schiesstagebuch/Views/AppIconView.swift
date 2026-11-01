import SwiftUI
import UIKit

/// Lets the user switch between the bundled app icons (Settings → App-Icon).
struct AppIconView: View {
    private struct Choice: Identifiable {
        let id: String?          // nil = primary icon
        let preview: String
        let title: LocalizedStringKey
    }

    private let choices = [
        Choice(id: nil, preview: "AppIconPreview", title: "Offenes Tagebuch"),
        Choice(id: "AppIconHardcover", preview: "AppIconHardcoverPreview", title: "Gebundenes Tagebuch"),
    ]

    @State private var current = UIApplication.shared.alternateIconName

    var body: some View {
        List(choices) { choice in
            Button {
                UIApplication.shared.setAlternateIconName(choice.id) { error in
                    if error == nil { current = choice.id }
                }
            } label: {
                HStack(spacing: 16) {
                    Image(choice.preview)
                        .resizable()
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 13.4, style: .continuous))
                    Text(choice.title).foregroundStyle(.primary)
                    Spacer()
                    if current == choice.id {
                        Image(systemName: "checkmark").foregroundStyle(.tint)
                    }
                }
            }
        }
        .navigationTitle("App-Icon")
    }
}
