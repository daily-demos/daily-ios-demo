import Foundation

/// Millisecond timing marks for the T-4717 join-latency repro.
///
/// Each mark is recorded once (the first time it is hit), logged to the
/// console, and folded into a short text summary that the call screen shows.
final class ReproTimer {
    static let shared = ReproTimer()

    struct Mark {
        let name: String
        let date: Date
        let deltaMs: Int
    }

    private(set) var marks: [Mark] = []
    private var firstDate: Date?
    private var extraLines: [String] = []

    /// Called on every change with the new summary text.
    var onChange: ((String) -> Void)?

    private let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    func reset(label: String) {
        self.marks = []
        self.firstDate = nil
        self.extraLines = ["run: \(label)"]
        print("[ReproTimer] reset (\(label))")
        self.onChange?(self.summary)
    }

    func mark(_ name: String) {
        guard !self.marks.contains(where: { $0.name == name }) else {
            return
        }
        let now = Date()
        if self.firstDate == nil {
            self.firstDate = now
        }
        let deltaMs = Int((now.timeIntervalSince(self.firstDate ?? now) * 1000).rounded())
        self.marks.append(Mark(name: name, date: now, deltaMs: deltaMs))
        print("[ReproTimer] \(name) \(self.formatter.string(from: now)) +\(deltaMs)ms")
        self.onChange?(self.summary)
    }

    /// Free-form line, used for the session and participant IDs.
    func note(_ line: String) {
        self.extraLines.append(line)
        print("[ReproTimer] \(line)")
        self.onChange?(self.summary)
    }

    var summary: String {
        var lines = self.extraLines
        for mark in self.marks {
            let time = self.formatter.string(from: mark.date)
            lines.append("\(mark.name): \(time) +\(mark.deltaMs)ms")
        }
        return lines.joined(separator: "\n")
    }
}
