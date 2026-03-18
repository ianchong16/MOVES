import Foundation

// MARK: - Streak Service
// Computes move completion streaks from SwiftData completion dates.
// A "streak" is consecutive calendar days with at least one completed move.
// Lightweight and stateless — computed on demand from the move list.

struct StreakService {

    // MARK: - Current Streak
    // Counts consecutive days with at least one completion, going backwards from today.
    // Returns 0 if no moves completed today or yesterday.
    static func currentStreak(completedMoves: [Move]) -> Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Get unique completion days, sorted newest first
        let completionDays: Set<Date> = Set(
            completedMoves.compactMap { $0.completedAt }
                .map { calendar.startOfDay(for: $0) }
        )

        guard !completionDays.isEmpty else { return 0 }

        // Streak must include today or yesterday to be "current"
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        guard completionDays.contains(today) || completionDays.contains(yesterday) else { return 0 }

        // Count backwards from the most recent day that qualifies
        let startDay = completionDays.contains(today) ? today : yesterday
        var streak = 0
        var checkDate = startDay

        while completionDays.contains(checkDate) {
            streak += 1
            guard let prevDay = calendar.date(byAdding: .day, value: -1, to: checkDate) else { break }
            checkDate = prevDay
        }

        return streak
    }

    // MARK: - Longest Streak
    // Returns the longest consecutive-day streak across all time.
    static func longestStreak(completedMoves: [Move]) -> Int {
        let calendar = Calendar.current

        let completionDays: [Date] = Array(Set(
            completedMoves.compactMap { $0.completedAt }
                .map { calendar.startOfDay(for: $0) }
        )).sorted()

        guard !completionDays.isEmpty else { return 0 }

        var longest = 1
        var current = 1

        for i in 1..<completionDays.count {
            let daysBetween = calendar.dateComponents([.day], from: completionDays[i - 1], to: completionDays[i]).day ?? 0
            if daysBetween == 1 {
                current += 1
                longest = max(longest, current)
            } else if daysBetween > 1 {
                current = 1
            }
            // daysBetween == 0 shouldn't happen (Set deduplication), but skip if it does
        }

        return longest
    }

    // MARK: - Streak Label
    // Returns a display string like "7-DAY STREAK" or nil if streak < 2.
    static func streakLabel(completedMoves: [Move]) -> String? {
        let streak = currentStreak(completedMoves: completedMoves)
        guard streak >= 2 else { return nil }
        return "\(streak)-DAY STREAK"
    }
}
