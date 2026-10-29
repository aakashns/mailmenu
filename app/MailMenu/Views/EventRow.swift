import SwiftUI

/// One upcoming event: title on the first line, time on the second, and a camera icon if it has a video call.
/// Clicking joins the video call (or opens the event if there is none); hovering shows a button to open the event in Google Calendar.
struct EventRow: View {
    let event: CalendarEvent
    let action: () -> Void
    let openInCalendar: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
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
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
            .onTapGesture(perform: action)
            .help(event.videoURL != nil ? "Join video call" : "Open in Google Calendar")
            if isHovered {
                Button(action: openInCalendar) {
                    Image(systemName: "calendar")
                }
                .buttonStyle(.borderless)
                .help("Open in Google Calendar")
            }
        }
        .rowStyle(isHovered: isHovered)
        .onHover { isHovered = $0 }
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
