import SwiftUI

struct PublishHUDView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 6) {
            if appState.isPublishing {
                ProgressView()
                    .controlSize(.small)
                Text("Publishing...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else if appState.lastPublishedURL != nil {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.caption)
                Text("Copied!")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else if let error = appState.publishError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                    .font(.caption)
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
