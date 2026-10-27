import SwiftUI

/// One upcoming event: title on the first line, time on the second, and a camera icon if it has a video call.
struct EventRow: View {
    let event: CalendarEvent
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.title)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                    Text(timeDescription)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if event.videoURL != nil {
                    Image(systemName: "video.fill")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.row)
        .help(event.videoURL != nil ? "Join video call" : "Open in Google Calendar")
    }

    private var timeDescription: String {
        func time(_ date: Date) -> String { date.formatted(date: .omitted, time: .shortened) }

        if event.start <= .now {
            return "Now · until \(time(event.end))"
        }
        let range = "\(time(event.start)) – \(time(event.end))"
        return Calendar.current.isDateInToday(event.start) ? range : "Tomorrow, \(range)"
    }
}
