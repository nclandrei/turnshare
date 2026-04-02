import SwiftUI

struct PublishHUDView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 6) {
            if appState.isPublishing {
                ProgressView()
                    .controlSize(.small)
                Text("Publishing...")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.text)
            } else if appState.lastPublishedURL != nil {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(Theme.accentGreen)
                    .font(.system(size: 13))
                Text("Copied!")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.text)
            } else if let error = appState.publishError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(Theme.accentRed)
                    .font(.system(size: 13))
                Text(error)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.accentRed)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .frame(height: 28)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .fixedSize()
    }
}
