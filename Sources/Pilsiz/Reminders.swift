import Foundation
import Observation
import UserNotifications

struct Reminder: Codable, Identifiable, Hashable {
    let channelNumber: Int
    let channelName: String
    let title: String
    let start: Date

    var id: String { "\(channelNumber)-\(Int(start.timeIntervalSince1970))" }
}

/// Program hatırlatıcıları: başlamadan 5 dk önce “Kanala geç” düğmeli bir macOS bildirimi.
@MainActor
@Observable
final class ReminderStore {
    static let lead: TimeInterval = 5 * 60
    nonisolated static let category = "PROGRAM_REMINDER"
    nonisolated static let switchAction = "SWITCH_CHANNEL"

    private(set) var reminders: [Reminder] = []
    private(set) var permissionDenied = false

    var upcoming: [Reminder] { reminders.filter { $0.start > Date() }.sorted { $0.start < $1.start } }

    init() {
        if let data = UserDefaults.standard.data(forKey: "reminders"),
           let saved = try? JSONDecoder().decode([Reminder].self, from: data) {
            reminders = saved
        }
        // Başlamış programların hatırlatıcıları atılır.
        reminders.removeAll { $0.start < Date() }
        save()
    }

    func isSet(channel: Channel, programme: Programme) -> Bool {
        reminders.contains { $0.channelNumber == channel.number && $0.start == programme.start }
    }

    func toggle(channel: Channel, programme: Programme) {
        if let existing = reminders.first(where: { $0.channelNumber == channel.number && $0.start == programme.start }) {
            remove(existing)
        } else {
            add(Reminder(channelNumber: channel.number, channelName: channel.name, title: programme.title, start: programme.start))
        }
    }

    func remove(_ reminder: Reminder) {
        reminders.removeAll { $0.id == reminder.id }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [reminder.id])
        save()
    }

    private func add(_ reminder: Reminder) {
        reminders.append(reminder)
        save()
        Task {
            let center = UNUserNotificationCenter.current()
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
            permissionDenied = !granted
            guard granted else { return }

            let content = UNMutableNotificationContent()
            content.title = "\(reminder.title) birazdan başlıyor"
            content.body = "\(reminder.channelName) · \(clock(reminder.start))"
            content.sound = .default
            content.categoryIdentifier = Self.category
            content.userInfo = ["channel": reminder.channelNumber]
            let delay = max(1, reminder.start.timeIntervalSinceNow - Self.lead)
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger))
        }
    }

    /// Bildirim kategorisi; uygulama açılışında bir kez kaydedilir.
    static func registerCategory() {
        let action = UNNotificationAction(identifier: switchAction, title: "Kanala geç")
        let category = UNNotificationCategory(identifier: Self.category, actions: [action], intentIdentifiers: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    private func save() {
        if let data = try? JSONEncoder().encode(reminders) {
            UserDefaults.standard.set(data, forKey: "reminders")
        }
    }
}
