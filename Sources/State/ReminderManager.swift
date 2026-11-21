import Foundation
import AppKit
@preconcurrency import UserNotifications

struct ScheduledReminderItem: Identifiable, Codable, Sendable {
    let id: String
    let text: String
    var target_iso: String
    var target_epoch: Double
    var formatted_time: String?
    let created_at: String
    var fired: Bool
    var recurrence: String?
}

@MainActor
final class ReminderManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published var upcomingReminders: [ScheduledReminderItem] = []

    var onReminderTriggered: ((ScheduledReminderItem) -> Void)?

    nonisolated(unsafe) private var timer: Timer?
    private var lastObservedModDate: Date?

    private let appSupportDir: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Shodha", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private var remindersFileURL: URL {
        appSupportDir.appendingPathComponent("reminders.json")
    }

    private var lockFileURL: URL {
        appSupportDir.appendingPathComponent(".reminders.lock")
    }

    override init() {
        super.init()
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        let snoozeAction = UNNotificationAction(
            identifier: "SNOOZE_10M",
            title: "Snooze 10 min",
            options: []
        )
        let dismissAction = UNNotificationAction(
            identifier: "DISMISS_REMINDER",
            title: "Done",
            options: []
        )

        // Category options ensure title & subtitle are always visible even if macOS hides previews
        let reminderCategory = UNNotificationCategory(
            identifier: "REMINDER",
            actions: [snoozeAction, dismissAction],
            intentIdentifiers: [],
            options: [.hiddenPreviewsShowTitle, .hiddenPreviewsShowSubtitle]
        )
        center.setNotificationCategories([reminderCategory])
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                self.appendLog("requestAuthorization granted=\(granted) error=\(error.localizedDescription)")
            }
        }

        loadReminders()
        startMonitoring()
    }

    deinit {
        timer?.invalidate()
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge, .list])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if response.actionIdentifier == "SNOOZE_10M" {
            let text = response.notification.request.content.body
            Task { @MainActor in
                self.snoozeReminder(text: text, minutes: 10)
            }
        }
        completionHandler()
    }

    func startMonitoring() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkReminders(forceReload: false)
            }
        }
    }

    func checkReminders(forceReload: Bool = true) {
        let now = Date().timeIntervalSince1970
        let modDate = (try? FileManager.default.attributesOfItem(atPath: remindersFileURL.path)[.modificationDate]) as? Date
        let fileChanged = (modDate != lastObservedModDate)
        let hasDueInMemory = upcomingReminders.contains(where: { $0.target_epoch <= now })

        if !forceReload && !fileChanged && !hasDueInMemory {
            return
        }

        var didFireAny = false
        var triggeredItems: [ScheduledReminderItem] = []

        let updatedList = withFileLock { () -> [ScheduledReminderItem] in
            var list = loadFromFileUnlocked()
            for i in 0..<list.count {
                if !list[i].fired && list[i].target_epoch <= now {
                    let triggeredSnapshot = list[i]
                    triggeredItems.append(triggeredSnapshot)
                    didFireAny = true

                    if let nextDate = nextOccurrence(after: Date(timeIntervalSince1970: list[i].target_epoch), recurrence: list[i].recurrence, now: Date()) {
                        list[i].target_epoch = nextDate.timeIntervalSince1970
                        list[i].target_iso = ISO8601DateFormatter().string(from: nextDate)
                        list[i].formatted_time = Self.formatDisplayDate(nextDate)
                        list[i].fired = false
                    } else {
                        list[i].fired = true
                    }
                }
            }

            if didFireAny {
                saveToFileUnlocked(list)
            }
            return list
        }

        lastObservedModDate = (try? FileManager.default.attributesOfItem(atPath: remindersFileURL.path)[.modificationDate]) as? Date

        for reminder in triggeredItems {
            self.onReminderTriggered?(reminder)
            self.postNotification(for: reminder)
        }

        self.upcomingReminders = updatedList
            .filter { !$0.fired && $0.target_epoch > now }
            .sorted(by: { $0.target_epoch < $1.target_epoch })
    }

    func addReminder(text: String, targetDate: Date, recurrence: String = "none") {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else { return }

        let now = Date()
        let item = ScheduledReminderItem(
            id: UUID().uuidString,
            text: cleanText,
            target_iso: ISO8601DateFormatter().string(from: targetDate),
            target_epoch: targetDate.timeIntervalSince1970,
            formatted_time: Self.formatDisplayDate(targetDate),
            created_at: ISO8601DateFormatter().string(from: now),
            fired: false,
            recurrence: recurrence
        )

        withFileLock {
            var list = loadFromFileUnlocked()
            list.append(item)
            saveToFileUnlocked(list)
        }
        checkReminders(forceReload: true)
    }

    func snoozeReminder(text: String, minutes: Int = 10) {
        let targetDate = Date().addingTimeInterval(TimeInterval(minutes * 60))
        addReminder(text: text, targetDate: targetDate, recurrence: "none")
    }

    func cancelReminder(id: String) {
        withFileLock {
            var list = loadFromFileUnlocked()
            list.removeAll { $0.id == id }
            saveToFileUnlocked(list)
        }
        checkReminders(forceReload: true)
    }

    func reload() {
        checkReminders(forceReload: true)
    }

    private func postNotification(for reminder: ScheduledReminderItem) {
        let content = UNMutableNotificationContent()
        content.title = "⏰ \(reminder.text)"
        content.subtitle = "Shodha Reminder"
        content.body = reminder.text
        content.categoryIdentifier = "REMINDER"
        content.sound = .default

        let req = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(req) { error in
            if let error = error {
                self.appendLog("add error=\(error.localizedDescription)")
            }
        }
    }

    private func nextOccurrence(after targetDate: Date, recurrence: String?, now: Date) -> Date? {
        guard let rec = recurrence?.lowercased(), rec != "none", !rec.isEmpty else {
            return nil
        }
        let cal = Calendar.current
        var next = targetDate

        func step(_ date: Date) -> Date? {
            switch rec {
            case "hourly":
                return cal.date(byAdding: .hour, value: 1, to: date)
            case "daily":
                return cal.date(byAdding: .day, value: 1, to: date)
            case "weekly":
                return cal.date(byAdding: .weekOfYear, value: 1, to: date)
            case "weekdays":
                var d = date
                repeat {
                    guard let candidate = cal.date(byAdding: .day, value: 1, to: d) else { return nil }
                    d = candidate
                } while cal.isDateInWeekend(d)
                return d
            default:
                return nil
            }
        }

        // Advance until strictly in the future (avoid firing back-to-back if Mac was asleep)
        var guardCount = 0
        while next <= now && guardCount < 1000 {
            guard let stepped = step(next) else { return nil }
            next = stepped
            guardCount += 1
        }
        return next > now ? next : nil
    }

    private static func formatDisplayDate(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "EEEE, MMM d 'at' h:mm a"
        return df.string(from: date)
    }

    private func withFileLock<T>(_ body: () -> T) -> T {
        let fd = open(lockFileURL.path, O_CREAT | O_RDWR, 0o600)
        if fd >= 0 {
            _ = flock(fd, LOCK_EX)
        }
        defer {
            if fd >= 0 {
                _ = flock(fd, LOCK_UN)
                _ = close(fd)
            }
        }
        return body()
    }

    private func loadFromFileUnlocked() -> [ScheduledReminderItem] {
        guard let data = try? Data(contentsOf: remindersFileURL),
              let items = try? JSONDecoder().decode([ScheduledReminderItem].self, from: data) else {
            return []
        }
        return items
    }

    private func saveToFileUnlocked(_ items: [ScheduledReminderItem]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: remindersFileURL, options: .atomic)
    }

    private func loadReminders() {
        let list = withFileLock { loadFromFileUnlocked() }
        lastObservedModDate = (try? FileManager.default.attributesOfItem(atPath: remindersFileURL.path)[.modificationDate]) as? Date
        let now = Date().timeIntervalSince1970
        self.upcomingReminders = list
            .filter { !$0.fired && $0.target_epoch > now }
            .sorted(by: { $0.target_epoch < $1.target_epoch })
    }

    nonisolated private func appendLog(_ message: String) {
        let logURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Shodha/notify.log")
        let line = "\(Date()) \(message)\n"
        guard let d = line.data(using: .utf8) else { return }
        if let h = try? FileHandle(forWritingTo: logURL) {
            h.seekToEndOfFile()
            h.write(d)
            try? h.close()
        } else {
            try? d.write(to: logURL)
        }
    }
}
