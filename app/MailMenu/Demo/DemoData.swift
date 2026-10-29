import Foundation

/// Made-up mailboxes and calendars for demo mode, in the shape of Gmail and Calendar API responses.
nonisolated enum DemoData {
    /// Actions on mail from this sender fail, to test how errors look.
    static let failingSender = "flaky@example.com"

    struct Mailbox {
        let email: String
        var messages: [Message]
        var events: [Event]
    }

    struct Message {
        let id: String
        let threadID: String
        let sender: String
        let subject: String
        let body: String
        var labels: Set<String>
        var listUnsubscribe: String?
        var listUnsubscribePost: String?

        func metadataJSON() -> [String: Any] {
            var headers = [["name": "From", "value": sender], ["name": "Subject", "value": subject]]
            if let listUnsubscribe { headers.append(["name": "List-Unsubscribe", "value": listUnsubscribe]) }
            if let listUnsubscribePost { headers.append(["name": "List-Unsubscribe-Post", "value": listUnsubscribePost]) }
            return ["id": id, "threadId": threadID, "labelIds": Array(labels), "payload": ["headers": headers]]
        }

        func fullJSON() -> [String: Any] {
            let data = Data(body.utf8).base64EncodedString()
                .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            return ["id": id, "payload": ["mimeType": "multipart/alternative", "parts": [
                ["mimeType": "text/plain", "body": ["data": data]],
            ]]]
        }
    }

    struct Event {
        let id: String
        let title: String
        let start: Date
        let end: Date
        var meetLink: String?
        var location: String?
        var description: String?
        var declined = false
        var allDay = false

        func json() -> [String: Any] {
            func time(_ date: Date) -> [String: Any] {
                allDay ? ["date": date.formatted(.iso8601.year().month().day())] : ["dateTime": date.formatted(.iso8601)]
            }
            var json: [String: Any] = [
                "id": id, "status": "confirmed", "eventType": "default", "summary": title,
                "start": time(start), "end": time(end),
                "htmlLink": "https://www.google.com/calendar/event?eid=\(id)",
            ]
            if let meetLink {
                json["conferenceData"] = ["entryPoints": [["entryPointType": "video", "uri": meetLink]]]
            }
            json["location"] = location
            json["description"] = description
            if declined { json["attendees"] = [["self": true, "responseStatus": "declined"]] }
            return json
        }
    }

    /// The first two are signed in at launch; "Continue with Google" adds the rest one at a time.
    static var mailboxes: [Mailbox] {
        [
            Mailbox(email: "alex@example.com", messages: workMessages, events: workEvents),
            Mailbox(email: "alex.personal@example.com", messages: personalMessages, events: personalEvents),
            Mailbox(email: "sam@example.org", messages: Array(personalMessages.prefix(3)), events: []),
        ]
    }

    private static let oneClick = "List-Unsubscribe=One-Click"

    private static var workMessages: [Message] {
        var messages = [
            message("Jordan Lee <jordan@example.com>", "Re: Launch checklist for Thursday",
                    "Thanks for pulling this together. I added two items under QA and moved the press embargo to 9am PT.\n\nCan you take a look before standup?",
                    thread: "t1"),
            message("Jordan Lee <jordan@example.com>", "Re: Launch checklist for Thursday", "One more thing: the status page copy still mentions the old plan names.", thread: "t1"),
            message("GitHub <notifications@github.com>", "[mailmenu] Fix layout flicker when deleting (#42)",
                    "@alex requested your review on this pull request.\n\n3 files changed, 120 additions, 80 deletions.",
                    unsubscribe: "<https://github.com/notifications/unsubscribe/abc>", post: oneClick),
            message("Priya Raman <priya@example.com>", "Lunch on Friday?", "There's a new ramen place near the office. 12:30 work for you?"),
            message("Flaky Bot <\(failingSender)>", "Actions on this message fail (demo)",
                    "Archive, delete or snooze this message to see how Mail Menu shows an error. The message comes back."),
            message("Linear <notifications@linear.app>", "3 issues assigned to you",
                    "MM-118 Panel resizes late when collapsing an account\nMM-121 Preview shows HTML entities\nMM-124 Count badge truncates",
                    unsubscribe: "<https://linear.app/unsubscribe/xyz>"),
            message("Calendly <notifications@calendly.com>", "New event: Intro call with Morgan", "Morgan Chen scheduled a 30 minute intro call with you for tomorrow at 2:00pm."),
            message("Stripe <receipts@stripe.com>", "Your receipt from Example Cloud #2291-4471", "Amount paid: $49.00\nDate paid: Oct 28, 2026\nPayment method: Visa ending in 4242"),
            message("The Weekly Byte <hello@weeklybyte.example>", "Issue #212: Menu bar apps are back",
                    "This week: why small utilities are having a moment, a deep dive into SwiftUI layout, and 6 tools we can't stop using.",
                    unsubscribe: "<mailto:unsubscribe@weeklybyte.example?subject=unsubscribe>"),
            message("Morgan Chen <morgan@example.org>", "Following up on the partnership deck", "Hi Alex, just checking whether you had a chance to review the deck I sent last week. Happy to walk through it."),
            message("Google Workspace <workspace-noreply@google.com>", "Your storage is 85% full", "You've used 25.5 GB of your 30 GB of storage."),
            message("Sam Patel <sam@example.org>", "Offsite agenda (draft)", "Day 1: roadmap review, customer panel, dinner.\nDay 2: team breakouts, retro, travel home."),
        ]
        let readMessages = [
            message("Jordan Lee <jordan@example.com>", "Notes from Monday's sync", "Decisions: ship the new onboarding behind a flag; revisit pricing in two weeks.", unread: false),
            message("Figma <no-reply@figma.com>", "Riley commented on Menu bar panel v3", "\"Can we try 8pt between rows instead of 6?\"", unread: false,
                    unsubscribe: "<https://www.figma.com/unsubscribe/123>", post: oneClick),
            message("AWS Billing <billing@aws.example>", "Your October invoice is available", "Total: $312.18. View the invoice in the Billing console.", unread: false),
            message("Riley Kim <riley@example.com>", "Icons for the settings page", "Attached are the SF Symbols alternatives we talked about.", unread: false),
            message("Notion <notify@notion.so>", "Weekly digest: 14 updates in Product", "Pages updated this week: Roadmap Q4, Launch plan, Hiring.", unread: false,
                    unsubscribe: "<https://www.notion.so/unsubscribe>"),
            message("Priya Raman <priya@example.com>", "Re: Interview loop for the iOS role", "Sounds good, I'll take the system design round.", unread: false),
            message("Zoom <no-reply@zoom.us>", "Cloud recording is now available", "Your recording of \"Design review\" is ready to view.", unread: false),
            message("Taylor Brooks <taylor@example.com>", "Coffee next week?", "I'm in town Tuesday through Thursday, would love to catch up.", unread: false),
            message("Product Hunt <hello@producthunt.example>", "Top products this week", "1. Mail Menu - your inbox in the menu bar\n2. ...", unread: false,
                    unsubscribe: "<https://www.producthunt.example/unsubscribe>", post: oneClick),
            message("Jordan Lee <jordan@example.com>", "Re: Hiring plan", "Approved. Let's open the req on Monday.", unread: false),
            message("Dropbox <no-reply@dropbox.com>", "Riley shared \"Brand assets\" with you", "Riley Kim invited you to view the folder \"Brand assets\".", unread: false),
            message("Ops Alerts <alerts@example.com>", "[Resolved] API latency above 500ms", "The alert \"API p95 latency\" was resolved at 3:42am.", unread: false),
            message("Casey Nguyen <casey@example.com>", "Welcome to the team!", "Excited to have you here. Here are a few docs to get started.", unread: false),
            message("Example Cloud <billing@example.cloud>", "Payment received", "Thanks! We received your payment of $49.00.", unread: false),
        ]
        messages += readMessages
        // Newest first, so unread and read mail are mixed like in a real inbox.
        return messages.enumerated()
            .sorted { ($0.offset % 3, $0.offset) < ($1.offset % 3, $1.offset) }
            .enumerated()
            .map { index, element in element.element.renumbered("w\(index)") }
    }

    private static var personalMessages: [Message] {
        [
            message("Mom <mom@example.net>", "Thanksgiving plans", "Are you flying in on Wednesday or Thursday? Let me know so Dad can pick you up."),
            message("Airline <noreply@airline.example>", "Check in now for your flight to SFO", "Your flight AL 284 departs tomorrow at 7:15am from JFK, gate B22."),
            message("Bookshop <orders@bookshop.example>", "Your order has shipped", "\"The Design of Everyday Things\" is on its way. Arriving Friday.",
                    unsubscribe: "<https://bookshop.example/unsubscribe>", post: oneClick),
            message("Chris Ortiz <chris@example.net>", "Climbing Saturday?", "Gym opens at 9. I can drive.", unread: false),
            message("Bank <alerts@bank.example>", "Your statement is ready", "Your October statement is now available.", unread: false),
            message("Running Club <club@running.example>", "Sunday long run: 10 miles", "Meet at the boathouse at 7am.", unread: false,
                    unsubscribe: "<mailto:leave@running.example>"),
        ].enumerated().map { index, message in message.renumbered("p\(index)") }
    }

    private static var workEvents: [Event] {
        let start = halfHourBefore(.now)
        return [
            Event(id: "e1", title: "Design review", start: start, end: start + 45 * 60, meetLink: "https://meet.google.com/abc-defg-hij"),
            Event(id: "e2", title: "1:1 with Jordan", start: start + 90 * 60, end: start + 120 * 60, location: "https://zoom.us/j/123456789"),
            Event(id: "e3", title: "Quarterly planning", start: start + 150 * 60, end: start + 210 * 60, declined: true),
            Event(id: "e4", title: "Lunch with Priya", start: start + 180 * 60, end: start + 240 * 60, location: "Ramen Bar"),
            Event(id: "e5", title: "Company holiday", start: start, end: start + 86400, allDay: true),
            Event(id: "e6", title: "Team standup", start: start + 20 * 3600, end: start + 20 * 3600 + 15 * 60,
                  description: "Join: https://teams.microsoft.com/l/meetup-join/abc"),
        ]
    }

    private static var personalEvents: [Event] {
        let start = halfHourBefore(.now)
        return [Event(id: "e7", title: "Dentist", start: start + 5 * 3600, end: start + 6 * 3600, location: "123 Main St")]
    }

    private static func halfHourBefore(_ date: Date) -> Date {
        Date(timeIntervalSinceReferenceDate: (date.timeIntervalSinceReferenceDate / 1800).rounded(.down) * 1800)
    }

    private static func message(_ sender: String, _ subject: String, _ body: String, unread: Bool = true, thread: String? = nil,
                                unsubscribe: String? = nil, post: String? = nil) -> Message {
        Message(id: "", threadID: thread ?? "", sender: sender, subject: subject, body: body,
                labels: unread ? ["INBOX", "UNREAD"] : ["INBOX"], listUnsubscribe: unsubscribe, listUnsubscribePost: post)
    }
}

private extension DemoData.Message {
    /// Gives the message its ID, and its own conversation unless it's part of an existing one.
    nonisolated func renumbered(_ id: String) -> Self {
        Self(id: id, threadID: threadID.isEmpty ? "thread-\(id)" : threadID, sender: sender, subject: subject, body: body,
             labels: labels, listUnsubscribe: listUnsubscribe, listUnsubscribePost: listUnsubscribePost)
    }
}
