import Foundation
import SwiftData

/// How long dictation history is kept before old entries are pruned.
enum HistoryRetention: String, CaseIterable, Identifiable {
    case day, week, month, threeMonths, year, forever

    var id: String { rawValue }

    var label: String {
        switch self {
        case .day:         return "1 day"
        case .week:        return "1 week"
        case .month:       return "1 month"
        case .threeMonths: return "3 months"
        case .year:        return "1 year"
        case .forever:     return "Forever"
        }
    }

    private var days: Int? {
        switch self {
        case .day:         return 1
        case .week:        return 7
        case .month:       return 30
        case .threeMonths: return 90
        case .year:        return 365
        case .forever:     return nil
        }
    }

    /// Entries created before this date should be removed. `nil` = keep forever.
    func cutoff(from now: Date = Date()) -> Date? {
        guard let days else { return nil }
        return Calendar.current.date(byAdding: .day, value: -days, to: now)
    }
}

@MainActor
enum HistoryMaintenance {
    /// Deletes history entries older than the retention window. No-op for `.forever`.
    static func prune(_ context: ModelContext, retention: HistoryRetention) {
        guard let cutoff = retention.cutoff() else { return }
        do {
            try context.delete(
                model: DictationEntry.self,
                where: #Predicate<DictationEntry> { $0.createdAt < cutoff }
            )
            try context.save()
        } catch {
            // Non-fatal — pruning will be retried on the next launch / setting change.
        }
    }
}
