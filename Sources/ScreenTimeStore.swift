import Foundation
import SwiftUI

@MainActor
final class ScreenTimeStore: ObservableObject {
    @AppStorage("nelly.dailyLimitMinutes") var dailyLimit = 45
    @AppStorage("nelly.usedSeconds") private var usedSeconds = 0
    @AppStorage("nelly.usageDay") private var usageDay = ""
    @Published private(set) var isPlaying = true

    var remainingSeconds: Int { max(0, dailyLimit * 60 - usedSeconds) }
    var isLimitReached: Bool { remainingSeconds <= 0 }

    init() { resetIfNewDay() }

    func tick() {
        resetIfNewDay()
        guard isPlaying, !isLimitReached else { return }
        usedSeconds += 1
        if isLimitReached { isPlaying = false }
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
