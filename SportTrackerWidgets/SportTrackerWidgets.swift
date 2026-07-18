import ActivityKit
import AppIntents
import Foundation
import SwiftUI
import WidgetKit

@main
struct SportTrackerWidgets: WidgetBundle {
    var body: some Widget {
        WorkoutStatusWidget()
        WorkoutLiveActivity()
    }
}

private struct WorkoutStatusEntry: TimelineEntry {
    let date: Date
}

private struct WorkoutStatusProvider: TimelineProvider {
    func placeholder(in context: Context) -> WorkoutStatusEntry { WorkoutStatusEntry(date: .now) }

    func getSnapshot(in context: Context, completion: @escaping (WorkoutStatusEntry) -> Void) {
        completion(WorkoutStatusEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WorkoutStatusEntry>) -> Void) {
        let entry = WorkoutStatusEntry(date: .now)
        let refreshDate = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now.addingTimeInterval(1_800)
        completion(Timeline(entries: [entry], policy: .after(refreshDate)))
    }
}

private struct WorkoutStatusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WorkoutStatusWidget", provider: WorkoutStatusProvider()) { _ in
            VStack(alignment: .leading, spacing: 8) {
                Label("Sport Tracker", systemImage: "figure.run.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.mint)
                Text("Готов к тренировке")
                    .font(.title3.bold())
                Text("Открой приложение и начни движение")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .containerBackground(.black.gradient, for: .widget)
        }
        .configurationDisplayName("Статус тренировки")
        .description("Быстрый доступ к Sport Tracker.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct WorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(context.attributes.workoutName, systemImage: "figure.run.circle.fill")
                        .font(.headline).foregroundStyle(.mint)
                    Spacer()
                    Text(context.state.isRunning ? "В ПРОЦЕССЕ" : "НА ПАУЗЕ")
                        .font(.caption2.bold()).foregroundStyle(context.state.isRunning ? .green : .orange)
                }
                HStack(spacing: 22) {
                    VStack(alignment: .leading, spacing: 3) {
                        workoutTime(context.state)
                        Text("время").font(.caption).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(context.state.distanceText).font(.system(.title2, design: .rounded).bold())
                        Text("дистанция").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                HStack(spacing: 10) {
                    if context.state.isRunning {
                        Button(intent: StopWorkoutIntent()) {
                            Label("Стоп", systemImage: "stop.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                    } else {
                        Button(intent: StartWorkoutIntent()) {
                            Label("Старт", systemImage: "play.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                    }
                }
            }
            .padding(.horizontal, 4)
            .activityBackgroundTint(.black.opacity(0.82))
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "figure.run.circle.fill").foregroundStyle(.mint)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.distanceText).font(.caption.bold())
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        workoutTime(context.state).monospacedDigit()
                        Spacer()
                        if context.state.isRunning {
                            Button(intent: StopWorkoutIntent()) { Label("Стоп", systemImage: "stop.fill") }
                        } else {
                            Button(intent: StartWorkoutIntent()) { Label("Старт", systemImage: "play.fill") }
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: "figure.run").foregroundStyle(.mint)
            } compactTrailing: {
                Text(context.state.distanceText).font(.caption2)
            } minimal: {
                Image(systemName: context.state.isRunning ? "figure.run" : "pause.fill")
            }
        }
    }

    @ViewBuilder
    private func workoutTime(_ state: WorkoutActivityAttributes.ContentState) -> some View {
        if state.isRunning {
            Text(state.startedAt, style: .timer)
                .font(.system(.title2, design: .rounded).bold())
        } else {
            Text(timeText(for: state.elapsedSeconds))
                .font(.system(.title2, design: .rounded).bold())
        }
    }

    private func timeText(for seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
