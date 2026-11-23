import Foundation
import SwiftUI

@MainActor
final class ScreenTimeStore: ObservableObject {
    @Published var dailyLimit: Int {
        didSet { UserDefaults.standard.set(dailyLimit, forKey: "nelly.dailyLimitMinutes") }
    }
    @Published private(set) var isPlaying = true
    private var usedSeconds: Int {
        didSet { UserDefaults.standard.set(usedSeconds, forKey: "nelly.usedSeconds") }
    }
    private var usageDay: String {
        didSet { UserDefaults.standard.set(usageDay, forKey: "nelly.usageDay") }
    }

    var remainingSeconds: Int { max(0, dailyLimit * 60 - usedSeconds) }
    var isLimitReached: Bool { remainingSeconds <= 0 }

    init() {
        dailyLimit = max(5, UserDefaults.standard.object(forKey: "nelly.dailyLimitMinutes") as? Int ?? 45)
        usedSeconds = UserDefaults.standard.integer(forKey: "nelly.usedSeconds")
        usageDay = UserDefaults.standard.string(forKey: "nelly.usageDay") ?? ""
        resetIfNewDay()
    }

    func tick() {
        resetIfNewDay()
        guard isPlaying, !isLimitReached else { return }
        usedSeconds += 1
        if isLimitReached {
            isPlaying = false
        }
    }

    func setPlaying(_ value: Bool) { isPlaying = value && !isLimitReached }
    func parentOverride() { usedSeconds = 0; isPlaying = true }
    func resetToday() { usedSeconds = 0; isPlaying = true }

    private func resetIfNewDay() {
        let today = Calendar.current.startOfDay(for: Date()).ISO8601Format()
        if usageDay != today {
            usageDay = today
            usedSeconds = 0
        }
    }
}
