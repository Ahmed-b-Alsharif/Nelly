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
            settingsUpdatedAt = Date().timeIntervalSince1970
            if isLimitReached { isPlaying = false }
        }
    }

    @Published private(set) var isPlaying = true
    @Published private(set) var isTimerRunning = false {
        didSet { UserDefaults.standard.set(isTimerRunning, forKey: "nelly.screenTimeRunning") }
    }
    @Published private(set) var usedSeconds: Int {
        didSet { UserDefaults.standard.set(usedSeconds, forKey: "nelly.usedSeconds") }
    }
    private var usageDay: String {
        didSet { UserDefaults.standard.set(usageDay, forKey: "nelly.usageDay") }
    }
    private var settingsUpdatedAt: Double {
        didSet { UserDefaults.standard.set(settingsUpdatedAt, forKey: "nelly.settingsUpdatedAt") }
    }
    private var resetAt: Double {
        didSet { UserDefaults.standard.set(resetAt, forKey: "nelly.screenTimeResetAt") }
    }

    var remainingSeconds: Int { max(0, dailyLimit * 60 - usedSeconds) }
    var isLimitReached: Bool { remainingSeconds <= 0 }
    var remainingTimeText: String {
        let minutes = remainingSeconds / 60
        let seconds = remainingSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    var sharedUsageDay: String { usageDay }
    var sharedSettingsUpdatedAt: Double { settingsUpdatedAt }
    var sharedResetAt: Double { resetAt }

    init() {
        let savedLimit = UserDefaults.standard.object(forKey: "nelly.dailyLimitMinutes") as? Int
        storedDailyLimit = min(240, max(1, savedLimit ?? 45))
        usedSeconds = UserDefaults.standard.integer(forKey: "nelly.usedSeconds")
        isTimerRunning = UserDefaults.standard.bool(forKey: "nelly.screenTimeRunning")
        usageDay = UserDefaults.standard.string(forKey: "nelly.usageDay") ?? ""
        let savedSettingsDate = UserDefaults.standard.double(forKey: "nelly.settingsUpdatedAt")
        settingsUpdatedAt = savedSettingsDate > 0 ? savedSettingsDate : (savedLimit == nil ? 0 : Date().timeIntervalSince1970)
        UserDefaults.standard.set(settingsUpdatedAt, forKey: "nelly.settingsUpdatedAt")
        resetAt = UserDefaults.standard.double(forKey: "nelly.screenTimeResetAt")
        resetIfNewDay()
    }

    func tick() {
        resetIfNewDay()
        guard isTimerRunning, !isLimitReached else {
            if isLimitReached { isTimerRunning = false; isPlaying = false }
            return
        }
        usedSeconds += 1
        if isLimitReached {
            isTimerRunning = false
            isPlaying = false
        }
    }

    func setPlaying(_ value: Bool) { isPlaying = value && !isLimitReached }

    func confirmDailyLimit(minutes: Int) {
        dailyLimit = minutes
        resetAt = Date().timeIntervalSince1970
        usedSeconds = 0
        isTimerRunning = true
        isPlaying = true
    }

    func parentOverride() {
        resetAt = Date().timeIntervalSince1970
        usedSeconds = 0
        isTimerRunning = true
        isPlaying = true
    }

    func resetToday() {
        resetAt = Date().timeIntervalSince1970
        usedSeconds = 0
        isTimerRunning = true
        isPlaying = true
    }

    func applySharedState(dailyLimit remoteLimit: Int, usedSeconds remoteSeconds: Int,
                          usageDay remoteDay: String, settingsUpdatedAt remoteUpdated: Double,
                          resetAt remoteReset: Double) {
        if remoteUpdated > settingsUpdatedAt {
            storedDailyLimit = min(240, max(1, remoteLimit))
            UserDefaults.standard.set(storedDailyLimit, forKey: "nelly.dailyLimitMinutes")
            settingsUpdatedAt = remoteUpdated
        }
        guard !remoteDay.isEmpty else { return }
        if remoteDay > usageDay {
            usageDay = remoteDay
            usedSeconds = max(0, remoteSeconds)
            resetAt = remoteReset
        } else if remoteDay == usageDay {
            if remoteReset > resetAt {
                resetAt = remoteReset
                usedSeconds = max(0, remoteSeconds)
            } else if remoteReset == resetAt {
                usedSeconds = max(usedSeconds, max(0, remoteSeconds))
            }
        }
        isTimerRunning = settingsUpdatedAt > 0 && resetAt > 0 && !isLimitReached
        if isLimitReached { isPlaying = false }
    }

    private func resetIfNewDay() {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: Date())
        if usageDay.isEmpty {
            // A newly paired phone must not treat its first local initialization
            // as a parent reset that overrides the family's shared usage.
            usageDay = today
            usedSeconds = 0
        } else if usageDay != today {
            usageDay = today
            usedSeconds = 0
            resetAt = Date().timeIntervalSince1970
            isTimerRunning = false
            isPlaying = false
        }
    }
}
