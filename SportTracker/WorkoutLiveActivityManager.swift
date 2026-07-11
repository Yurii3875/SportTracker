import ActivityKit
import Foundation

@MainActor
final class WorkoutLiveActivityManager: ObservableObject {
    private var activity: Activity<WorkoutActivityAttributes>?

    init() {
        activity = Activity<WorkoutActivityAttributes>.activities.first
    }

    func start(workoutName: String, startedAt: Date) {
        guard activity == nil, ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = WorkoutActivityAttributes(workoutName: workoutName)
        let state = WorkoutActivityAttributes.ContentState(
            isRunning: true,
            startedAt: startedAt,
            elapsedSeconds: 0,
            distanceMeters: 0
        )
        activity = try? Activity.request(
            attributes: attributes,
            content: ActivityContent(state: state, staleDate: nil),
            pushType: nil
        )
    }

    func update(isRunning: Bool, startedAt: Date, elapsedSeconds: Int, distanceMeters: Double) {
        guard let activity else { return }
        let state = WorkoutActivityAttributes.ContentState(
            isRunning: isRunning,
            startedAt: startedAt,
            elapsedSeconds: elapsedSeconds,
            distanceMeters: distanceMeters
        )
        Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
    }

    func end(elapsedSeconds: Int, distanceMeters: Double) {
        guard let activity else { return }
        let state = WorkoutActivityAttributes.ContentState(
            isRunning: false,
            startedAt: .now,
            elapsedSeconds: elapsedSeconds,
            distanceMeters: distanceMeters
        )
        Task { await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .immediate) }
        self.activity = nil
    }
}
