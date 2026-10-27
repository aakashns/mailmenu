import Foundation

/// A timed event on the user's calendar.
struct CalendarEvent: Identifiable, Hashable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let videoURL: URL?
    let htmlLink: URL?
    let accountEmail: String

    /// The video call if there is one, otherwise the event in Google Calendar (in the right account).
    var url: URL? {
        videoURL ?? htmlLink.flatMap { URL(string: $0.absoluteString + "&authuser=\(accountEmail.urlQueryValueEncoded)") }
    }
}

/// Read-only client for the Google Calendar API (https://developers.google.com/calendar/api/v3/reference).
struct CalendarClient {
    let api: GoogleAPI

    init(accessToken: String) {
        api = GoogleAPI(accessToken: accessToken)
    }

    private static let baseURL = URL(string: "https://www.googleapis.com/calendar/v3")!

    /// Timed events on the primary calendar that overlap the given range (including ones already
    /// in progress), excluding cancelled events, declined invitations, and working location entries.
    func events(from start: Date, to end: Date, accountEmail: String) async throws -> [CalendarEvent] {
        let list: EventList = try await api.get(Self.baseURL.appending(path: "calendars/primary/events"), query: [
            URLQueryItem(name: "timeMin", value: start.formatted(.iso8601)),
            URLQueryItem(name: "timeMax", value: end.formatted(.iso8601)),
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "orderBy", value: "startTime"),
            URLQueryItem(name: "maxResults", value: "50"),
        ])
        return (list.items ?? []).compactMap { event in
            guard event.status != "cancelled",
                  event.eventType != "workingLocation",
                  event.attendees?.first(where: { $0.isSelf == true })?.responseStatus != "declined",
                  let start = event.start.dateTime.flatMap(Self.parseDate),
                  let end = event.end.dateTime.flatMap(Self.parseDate)
            else { return nil }

            let title = event.summary?.trimmingCharacters(in: .whitespaces) ?? ""
            return CalendarEvent(
                id: "\(accountEmail)/\(event.id)",
                title: title.isEmpty ? "(No title)" : title,
                start: start,
                end: end,
                videoURL: Self.videoURL(for: event),
                htmlLink: event.htmlLink.flatMap(URL.init(string:)),
                accountEmail: accountEmail
            )
        }
    }

    private static func parseDate(_ string: String) -> Date? {
        ISO8601DateFormatter().date(from: string)
    }

    /// Google Meet or conferencing add-on links first, then Zoom/Teams/etc. links pasted into the
    /// location or description (common for invites sent from Outlook).
    private static func videoURL(for event: Event) -> URL? {
        if let uri = event.conferenceData?.entryPoints?.first(where: { $0.entryPointType == "video" })?.uri {
            return URL(string: uri)
        }
        if let link = event.hangoutLink {
            return URL(string: link)
        }
        return [event.location, event.description].lazy.compactMap { $0 }.compactMap(firstVideoCallLink).first
    }
}

private let videoCallHosts = ["meet.google.com", "zoom.us", "teams.microsoft.com", "teams.live.com", "webex.com", "whereby.com"]

/// Finds the first link to a known video call service in free-form text.
func firstVideoCallLink(in text: String) -> URL? {
    guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
    let matches = detector.matches(in: text, range: NSRange(text.startIndex..., in: text))
    return matches.lazy.compactMap(\.url).first { url in
        guard let host = url.host()?.lowercased() else { return false }
        return videoCallHosts.contains { host == $0 || host.hasSuffix(".\($0)") }
    }
}

private struct EventList: Decodable {
    let items: [Event]?
}

private struct Event: Decodable {
    /// Timed events have `dateTime`; all-day events have `date` instead.
    struct Time: Decodable { let dateTime: String? }

    struct Attendee: Decodable {
        let isSelf: Bool?
        let responseStatus: String?

        enum CodingKeys: String, CodingKey {
            case isSelf = "self"
            case responseStatus
        }
    }

    struct ConferenceData: Decodable {
        struct EntryPoint: Decodable { let entryPointType: String; let uri: String }
        let entryPoints: [EntryPoint]?
    }

    let id: String
    let status: String?
    let eventType: String?
    let summary: String?
    let start: Time
    let end: Time
    let htmlLink: String?
    let hangoutLink: String?
    let location: String?
    let description: String?
    let attendees: [Attendee]?
    let conferenceData: ConferenceData?
}
