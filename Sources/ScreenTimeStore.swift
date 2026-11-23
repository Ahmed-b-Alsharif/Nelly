import Foundation
import SwiftUI

@MainActor
final class ScreenTimeStore: ObservableObject {
    @Published private var storedDailyLimit: Int
    var dailyLimit: Int {
        get { storedDailyLimit }
        set {
            let bounded = min(240, max(1, newValue))
            storedDailyLimit = bounded
            UserDefaults.standard.set(bounded, forKey: "nelly.dailyLimitMinutes")
            if isLimitReached { isPlaying = false }
        }
    }

    @Published private(set) var isPlaying = true
    @Published private(set) var usedSeconds: Int {
        didSet { UserDefaults.standard.set(usedSeconds, forKey: "nelly.usedSeconds") }
    }
    private var usageDay: String {
        didSet { UserDefaults.standard.set(usageDay, forKey: "nelly.usageDay") }
    }

    var remainingSeconds: Int { max(0, dailyLimit * 60 - usedSeconds) }
    var isLimitReached: Bool { remainingSeconds <= 0 }

    init() {
        storedDailyLimit = min(240, max(1, UserDefaults.standard.object(forKey: "nelly.dailyLimitMinutes") as? Int ?? 45))
        usedSeconds = UserDefaults.standard.integer(forKey: "nelly.usedSeconds")
        usageDay = UserDefaults.standard.string(forKey: "nelly.usageDay") ?? ""
        resetIfNewDay()
    }

    func tick() {
        resetIfNewDay()
        guard !isLimitReached else { isPlaying = false; return }
        usedSeconds += 1
        if isLimitReached { isPlaying = false }
    }

    func setPlaying(_ value: Bool) { isPlaying = value && !isLimitReached }
    func parentOverride() { usedSeconds = 0; isPlaying = true }
    func resetToday() { usedSeconds = 0; isPlaying = true }

    private func resetIfNewDay() {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: Date())
        if usageDay != today {
            usageDay = today
            usedSeconds = 0
        }
    }
}
