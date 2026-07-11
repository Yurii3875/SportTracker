import ActivityKit
import AppIntents
import Foundation

struct WorkoutActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var isRunning: Bool
        var startedAt: Date
        var elapsedSeconds: Int
        var distanceMeters: Double

        var distanceText: String {
            distanceMeters >= 1_000
                ? String(format: "%.2f км", distanceMeters / 1_000)
                : "\(Int(distanceMeters.rounded())) м"
        }
    }

    var workoutName: String
}

enum WorkoutControlStore {
    private static let requestKey = "liveActivityRequestedRunning"
    private static let suiteName = "group.com.example.SportTracker4564536"
    private static var defaults: UserDefaults { UserDefaults(suiteName: suiteName) ?? .standard }

    static func requestRunning(_ shouldRun: Bool) {
        defaults.set(shouldRun, forKey: requestKey)
    }

    static func consumeRequestedRunning() -> Bool? {
        guard defaults.object(forKey: requestKey) != nil else { return nil }
        let requested = defaults.bool(forKey: requestKey)
        defaults.removeObject(forKey: requestKey)
        return requested
    }
}

struct StartWorkoutIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Продолжить тренировку"

    func perform() async throws -> some IntentResult {
        WorkoutControlStore.requestRunning(true)
        for activity in Activity<WorkoutActivityAttributes>.activities {
            let state = activity.content.state
            let resumed = WorkoutActivityAttributes.ContentState(
                isRunning: true,
                startedAt: .now,
                elapsedSeconds: state.elapsedSeconds,
                distanceMeters: state.distanceMeters
            )
            await activity.update(ActivityContent(state: resumed, staleDate: nil))
        }
        return .result()
    }
}

struct StopWorkoutIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Поставить тренировку на паузу"

    func perform() async throws -> some IntentResult {
        WorkoutControlStore.requestRunning(false)
        for activity in Activity<WorkoutActivityAttributes>.activities {
            let state = activity.content.state
            let pausedElapsed = state.isRunning
                ? state.elapsedSeconds + Int(Date.now.timeIntervalSince(state.startedAt))
                : state.elapsedSeconds
            let paused = WorkoutActivityAttributes.ContentState(
                isRunning: false,
                startedAt: .now,
                elapsedSeconds: pausedElapsed,
                distanceMeters: state.distanceMeters
            )
            await activity.update(ActivityContent(state: paused, staleDate: nil))
        }
        return .result()
    }
}

