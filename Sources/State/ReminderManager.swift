import Foundation
import AppKit
import UserNotifications

struct ScheduledReminderItem: Identifiable, Codable {
    let id: String
    let text: String
    let target_iso: String
    let target_epoch: Double
    let formatted_time: String?
    let created_at: String
    var fired: Bool
}

@MainActor
final class ReminderManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published var upcomingReminders: [ScheduledReminderItem] = []
    
    var onReminderTriggered: ((ScheduledReminderItem) -> Void)?
    
    private var timer: Timer?
    private let remindersFileURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Shodha", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("reminders.json")
    }()
    
    override init() {
        super.init()
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        
        // Category options ensure title & subtitle are always visible even if macOS hides previews
        let reminderCategory = UNNotificationCategory(
            identifier: "REMINDER",
            actions: [],
            intentIdentifiers: [],
            options: [.hiddenPreviewsShowTitle, .hiddenPreviewsShowSubtitle]
        )
        center.setNotificationCategories([reminderCategory])
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            let line = "\(Date()) requestAuthorization granted=\(granted) error=\(String(describing: error))\n"
            let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("Shodha/notify.log")
            if let d = line.data(using: .utf8) {
                if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(d); try? h.close() } else { try? d.write(to: url) }
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
    
    func startMonitoring() {
        timer?.invalidate()
        // Check every 1 second for exact-second trigger precision
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkReminders()
            }
        }
    }
    
    func checkReminders() {
        var list = loadFromFile()
        let now = Date().timeIntervalSince1970
        var didFireAny = false
        
        for i in 0..<list.count {
            if !list[i].fired && list[i].target_epoch <= now {
                list[i].fired = true
                didFireAny = true
                let reminder = list[i]
                
                // Trigger reminder event in AppState!
                self.onReminderTriggered?(reminder)
                
                // Native notification with the chosen avatar icon and title text
                let content = UNMutableNotificationContent()
                content.title = "⏰ \(reminder.text)"
                content.subtitle = "Shodha Reminder"
                content.body = reminder.text
                content.categoryIdentifier = "REMINDER"
                content.sound = .default
                
                // The header icon is the app bundle icon, which AppState keeps in sync with the chosen avatar.
                let notificationContent = content
                
                let req = UNNotificationRequest(
                    identifier: UUID().uuidString,
                    content: notificationContent,
                    trigger: nil
                )
                let logURL = remindersFileURL.deletingLastPathComponent().appendingPathComponent("notify.log")
                UNUserNotificationCenter.current().getNotificationSettings { s in
                    let line = "\(Date()) auth=\(s.authorizationStatus.rawValue) alert=\(s.alertSetting.rawValue) style=\(s.alertStyle.rawValue)\n"
                    if let d = line.data(using: .utf8) {
                        if let h = try? FileHandle(forWritingTo: logURL) { h.seekToEndOfFile(); h.write(d); try? h.close() }
                        else { try? d.write(to: logURL) }
                    }
                }
                UNUserNotificationCenter.current().add(req) { error in
                    let line = "\(Date()) add error=\(String(describing: error))\n"
                    if let d = line.data(using: .utf8), let h = try? FileHandle(forWritingTo: logURL) {
                        h.seekToEndOfFile(); h.write(d); try? h.close()
                    }
                }
            }
        }
        
        if didFireAny {
            saveToFile(list)
        }
        
        // Update upcoming list (non-fired, future)
        self.upcomingReminders = list.filter { !$0.fired && $0.target_epoch > now }
            .sorted(by: { $0.target_epoch < $1.target_epoch })
    }
    
    func cancelReminder(id: String) {
        var list = loadFromFile()
        list.removeAll { $0.id == id }
        saveToFile(list)
        checkReminders()
    }
    
    func reload() {
        checkReminders()
    }
    
    private func loadFromFile() -> [ScheduledReminderItem] {
        guard let data = try? Data(contentsOf: remindersFileURL),
              let items = try? JSONDecoder().decode([ScheduledReminderItem].self, from: data) else {
            return []
        }
        return items
    }
    
    private func saveToFile(_ items: [ScheduledReminderItem]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: remindersFileURL, options: .atomic)
    }
    
    private func loadReminders() {
        let list = loadFromFile()
        let now = Date().timeIntervalSince1970
        self.upcomingReminders = list.filter { !$0.fired && $0.target_epoch > now }
            .sorted(by: { $0.target_epoch < $1.target_epoch })
    }
}
