import SwiftUI

/// One unread message: sender name and email on the first line, subject on the second.
struct MessageRow: View {
    let message: UnreadMessage
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if let name = message.senderName {
                        Text(name).fontWeight(.semibold)
                        Text(message.senderEmail).foregroundStyle(.secondary)
                    } else {
                        Text(message.senderEmail).fontWeight(.semibold)
                    }
                }
                .lineLimit(1)

                Text(message.subject.isEmpty ? "(no subject)" : message.subject)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.row)
    }
}
