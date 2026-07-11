import SwiftUI
import HealthKit
import MapKit
import CoreLocation
import ActivityKit

@main
struct SportTrackerApp: App {
    var body: some Scene { WindowGroup { AppRootView() } }
}

struct AppRootView: View {
    @AppStorage("profileComplete") private var profileComplete = false
    var body: some View {
        if profileComplete { ContentView() } else { RegistrationView() }
    }
}

enum Gender: String, CaseIterable, Identifiable {
    case female = "Женский", male = "Мужской", unspecified = "Не указывать"
    var id: String { rawValue }
}

struct BodyNorm {
    let weight: Double
    let height: Double
    let age: Int
    let gender: Gender
    private var meters: Double { height / 100 }
    var bmi: Double { guard meters > 0 else { return 0 }; return weight / (meters * meters) }
    var healthyMinWeight: Double { 18.5 * meters * meters }
    var healthyMaxWeight: Double { 24.9 * meters * meters }
    var basalCalories: Int {
        let genderAdjustment = gender == .male ? 5.0 : gender == .female ? -161.0 : -78.0
        return Int((10 * weight + 6.25 * height - 5 * Double(age) + genderAdjustment).rounded())
    }
    var healthyRange: String { "\(Int(healthyMinWeight.rounded()))–\(Int(healthyMaxWeight.rounded())) кг" }
}

enum WorkoutType: String, CaseIterable, Identifiable, Codable {
    case running = "Бег", cycling = "Велосипед", strength = "Силовая", yoga = "Йога"
    var id: String { rawValue }
    var symbol: String { switch self { case .running: "figure.run"; case .cycling: "bicycle"; case .strength: "dumbbell.fill"; case .yoga: "figure.mind.and.body" } }
    var color: Color { switch self { case .running: .orange; case .cycling: .cyan; case .strength: .purple; case .yoga: .pink } }
}

struct Workout: Identifiable {
    let id = UUID(); var type: WorkoutType; var duration: Int; var calories: Int; var date: Date = .now
}

struct WorkoutTemplate: Identifiable {
    let id = UUID(); let title: String; let subtitle: String; let type: WorkoutType; let minutes: Int
    static let all = [
        WorkoutTemplate(title: "Лёгкий бег", subtitle: "Ровный темп для выносливости", type: .running, minutes: 30),
        WorkoutTemplate(title: "Интервалы", subtitle: "Бег с ускорениями", type: .running, minutes: 20),
        WorkoutTemplate(title: "Силовая база", subtitle: "Тренировка всего тела", type: .strength, minutes: 45),
        WorkoutTemplate(title: "Велопрогулка", subtitle: "Кардио в комфортном темпе", type: .cycling, minutes: 40),
        WorkoutTemplate(title: "Мягкая йога", subtitle: "Подвижность и восстановление", type: .yoga, minutes: 25)
    ]
}

final class HealthManager: ObservableObject {
    private let store = HKHealthStore()
    @Published var isConnected = false

    func requestAccess() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let share: Set = [HKObjectType.workoutType(), HKQuantityType(.activeEnergyBurned)]
        store.requestAuthorization(toShare: share, read: []) { success, _ in
            DispatchQueue.main.async { self.isConnected = success }
        }
    }

    func save(workout: Workout, startedAt: Date, distanceMeters: CLLocationDistance = 0) {
        guard isConnected else { return }
        let type: HKWorkoutActivityType = switch workout.type { case .running: .running; case .cycling: .cycling; case .strength: .traditionalStrengthTraining; case .yoga: .yoga }
        let energy = HKQuantity(unit: .kilocalorie(), doubleValue: Double(workout.calories))
        let distance: HKQuantity? = [.running, .cycling].contains(workout.type) && distanceMeters > 0
            ? HKQuantity(unit: .meter(), doubleValue: distanceMeters)
            : nil
        let item = HKWorkout(activityType: type, start: startedAt, end: workout.date, duration: TimeInterval(workout.duration * 60), totalEnergyBurned: energy, totalDistance: distance, metadata: nil)
        store.save(item) { _, _ in }
    }
}

struct ContentView: View {
    @State private var workouts = [Workout(type: .running, duration: 35, calories: 320), Workout(type: .strength, duration: 50, calories: 410, date: .now.addingTimeInterval(-86_400))]
    @State private var selectedType: WorkoutType = .running
    @State private var seconds = 0
    @State private var isRunning = false
    @State private var goalMinutes = 30
    @State private var showHistory = false
    @State private var showTemplates = false
    @State private var showGoals = false
    @State private var showFinishState = false
    @State private var startedAt = Date()
    @State private var mapPosition: MapCameraPosition = .automatic
    @StateObject private var health = HealthManager()
    @StateObject private var locationManager = WorkoutLocationManager()
    @StateObject private var liveActivity = WorkoutLiveActivityManager()
    @AppStorage("preferredSessionMinutes") private var preferredSessionMinutes = 30
    @AppStorage("weeklyGoalMinutes") private var weeklyGoalMinutes = 180
    @AppStorage("currentWeight") private var currentWeight = 84.0
    @AppStorage("targetWeight") private var targetWeight = 72.0
    @AppStorage("height") private var height = 178.0
    @AppStorage("userName") private var userName = ""
    @AppStorage("userAge") private var userAge = 25
    @AppStorage("userGender") private var storedGender = Gender.unspecified.rawValue
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var progress: Double { min(Double(seconds) / Double(max(goalMinutes, 1) * 60), 1) }
    private var calories: Int { Int(Double(seconds) / 60 * 9.5) }
    private var time: String { String(format: "%02d:%02d", seconds / 60, seconds % 60) }
    private var workoutReachedGoal: Bool { seconds >= goalMinutes * 60 }
    private var mascotIsTired: Bool { showFinishState || workoutReachedGoal }
    private var weekStart: Date {
        Calendar(identifier: .iso8601).dateInterval(of: .weekOfYear, for: .now)?.start ?? .now
    }
    private var weeklyWorkouts: [Workout] {
        workouts.filter { $0.date >= weekStart && $0.date <= .now }
    }
    private var weeklyMinutes: Int { weeklyWorkouts.reduce(0) { $0 + $1.duration } }
    private var weeklyProgress: Double { min(Double(weeklyMinutes) / Double(max(weeklyGoalMinutes, 1)), 1) }
    private var weeklyRemaining: Int { max(weeklyGoalMinutes - weeklyMinutes, 0) }
    private var weekdayMinutes: [Int] {
        let calendar = Calendar(identifier: .iso8601)
        return (0..<7).map { dayOffset in
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: weekStart) else { return 0 }
            return weeklyWorkouts.filter { calendar.isDate($0.date, inSameDayAs: day) }.reduce(0) { $0 + $1.duration }
        }
    }
    private var goalBinding: Binding<Int> {
        Binding(
            get: { goalMinutes },
            set: { newValue in
                goalMinutes = newValue
                preferredSessionMinutes = newValue
            }
        )
    }
    private var bodyNorm: BodyNorm { BodyNorm(weight: currentWeight, height: height, age: userAge, gender: Gender(rawValue: storedGender) ?? .unspecified) }
    private var bmi: Double { bodyNorm.bmi }
    private var healthyUpperWeight: Double { bodyNorm.healthyMaxWeight }
    private var personalGoal: Double { max(currentWeight - targetWeight, 0) }
    private var recommendedLoss: Double { max(currentWeight - healthyUpperWeight, 0) }
    private var planWeeks: Int { max(Int(ceil(personalGoal / 0.5)), 0) }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(colors: [Color(red: 0.04, green: 0.06, blue: 0.14), Color(red: 0.10, green: 0.08, blue: 0.24)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 22) {
                        header
                        picker
                        chooseWorkoutButton
                        goalsCard
                        healthButton
                        timerCard
                        metrics
                        routeCard
                        adviceCard
                        weightPlan
                        weeklyCard
                    }
                    .padding(.horizontal, 20).padding(.bottom, 28)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showHistory) { HistoryView(workouts: workouts) }
            .sheet(isPresented: $showTemplates) { WorkoutPickerView { template in selectedType = template.type; goalMinutes = template.minutes } }
            .sheet(isPresented: $showGoals) {
                GoalSettingsView(sessionMinutes: $preferredSessionMinutes, weeklyMinutes: $weeklyGoalMinutes) {
                    goalMinutes = preferredSessionMinutes
                }
            }
            .onAppear { goalMinutes = preferredSessionMinutes }
            .onReceive(ticker) { _ in
                applyLockScreenControl()
                guard isRunning else { return }
                seconds += 1
                if workoutReachedGoal { pauseWorkout() }
                syncLiveActivity()
            }
            .onReceive(locationManager.$totalDistance) { _ in
                if isRunning { syncLiveActivity() }
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("МОЙ СПОРТ").font(.caption.weight(.bold)).tracking(2).foregroundStyle(.cyan)
                Text(userName.isEmpty ? "Время двигаться" : "Вперёд, \(userName)!").font(.largeTitle.bold()).foregroundStyle(.white)
            }
            Spacer()
            Button { showHistory = true } label: {
                Image(systemName: "chart.bar.fill").font(.title3.bold()).foregroundStyle(.white)
                    .frame(width: 46, height: 46).background(.white.opacity(0.12), in: Circle())
            }
        }.padding(.top, 12)
    }

    private var picker: some View {
        HStack(spacing: 10) {
            ForEach(WorkoutType.allCases) { type in
                Button { if !isRunning { selectedType = type } } label: {
                    VStack(spacing: 7) {
                        Image(systemName: type.symbol).font(.title3)
                        Text(type.rawValue).font(.caption2.weight(.semibold))
                    }
                    .foregroundStyle(selectedType == type ? .white : .white.opacity(0.55))
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(selectedType == type ? type.color.opacity(0.85) : .white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                }.buttonStyle(.plain)
            }
        }
    }

    private var timerCard: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle().stroke(.white.opacity(0.10), lineWidth: 18)
                Circle().trim(from: 0, to: progress).stroke(AngularGradient(colors: [selectedType.color, .cyan, selectedType.color], center: .center), style: StrokeStyle(lineWidth: 18, lineCap: .round))
                    .rotationEffect(.degrees(-90)).animation(.easeInOut(duration: 0.3), value: progress)
                VStack(spacing: 2) {
                    WorkoutMascotView(type: selectedType, isRunning: isRunning, isTired: mascotIsTired)
                        .frame(width: 168, height: 128)
                    Text(time).font(.system(size: 46, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(.white)
                    Text("из \(goalMinutes) минут").font(.subheadline).foregroundStyle(.white.opacity(0.55))
                }
            }.frame(width: 270, height: 270).padding(.vertical, 8)
            HStack(spacing: 12) {
                Button {
                    isRunning ? pauseWorkout() : resumeWorkout()
                } label: {
                    Label(isRunning ? "Пауза" : "Начать", systemImage: isRunning ? "pause.fill" : "play.fill")
                        .font(.headline).foregroundStyle(.black).frame(maxWidth: .infinity).padding(.vertical, 17)
                        .background(.white, in: Capsule())
                }
                Button { resetWorkout() } label: {
                    Image(systemName: "arrow.counterclockwise").font(.headline).foregroundStyle(.white).frame(width: 56, height: 56)
                        .background(.white.opacity(0.13), in: Circle())
                }
            }
            HStack { Text("Цель тренировки: \(goalMinutes) мин"); Spacer(); Stepper("", value: goalBinding, in: 5...120, step: 5).labelsHidden().tint(.cyan) }
                .font(.subheadline.weight(.medium)).foregroundStyle(.white.opacity(0.75)).padding(.horizontal, 8)
            if seconds > 0 {
                Button { finishWorkout() } label: {
                    Label(workoutReachedGoal ? "Сохранить результат" : "Завершить и сохранить", systemImage: "checkmark.circle.fill").font(.subheadline.bold()).foregroundStyle(.cyan)
                }
            }
        }
        .padding(22).background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 30))
        .overlay(RoundedRectangle(cornerRadius: 30).stroke(.white.opacity(0.13)))
    }

    private var metrics: some View {
        HStack(spacing: 10) {
            MetricCard(value: "\(calories)", title: "ккал сожжено", icon: "flame.fill", color: .orange)
            MetricCard(value: "\(Int(progress * 100))%", title: "выполнено", icon: "target", color: .cyan)
            MetricCard(value: locationManager.distanceText, title: "дистанция", icon: "figure.run", color: .mint)
        }
    }

    private var chooseWorkoutButton: some View {
        Button { showTemplates = true } label: {
            HStack { Image(systemName: "square.grid.2x2.fill"); Text("Выбрать тренировку").fontWeight(.semibold); Spacer(); Image(systemName: "chevron.right") }
                .foregroundStyle(.white).padding(16).background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 18))
        }.buttonStyle(.plain).disabled(isRunning)
    }

    private var goalsCard: some View {
        Button { showGoals = true } label: {
            HStack(spacing: 13) {
                Image(systemName: "target").font(.title3).foregroundStyle(.cyan)
                    .frame(width: 42, height: 42).background(.cyan.opacity(0.14), in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text("ЦЕЛИ НА НЕДЕЛЮ").font(.caption2.bold()).tracking(1.1).foregroundStyle(.cyan)
                    Text("\(weeklyMinutes) из \(weeklyGoalMinutes) мин").font(.subheadline.bold()).foregroundStyle(.white)
                    ProgressView(value: weeklyProgress).tint(.cyan).frame(maxWidth: .infinity)
                }
                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.white.opacity(0.55))
            }
            .padding(15).background(.cyan.opacity(0.09), in: RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }

    private var healthButton: some View {
        Button { health.requestAccess() } label: {
            HStack(spacing: 11) {
                Image(systemName: health.isConnected ? "heart.fill" : "heart.circle.fill").foregroundStyle(.red)
                VStack(alignment: .leading, spacing: 2) { Text(health.isConnected ? "Apple Health подключён" : "Подключить Apple Health").font(.subheadline.bold()); Text(health.isConnected ? "Тренировки и ккал будут сохраняться" : "Сохранять тренировки и активные ккал").font(.caption2).foregroundStyle(.white.opacity(0.58)) }
                Spacer()
                if !health.isConnected { Image(systemName: "plus").fontWeight(.bold) }
            }.foregroundStyle(.white).padding(14).background(.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 18))
        }.buttonStyle(.plain)
    }

    private var adviceCard: some View {
        let advice = seconds > 0 ? "Дыши ровно и держи комфортный темп — стабильность важнее скорости." : "Начинай с лёгкой разминки 5–10 минут и выбирай нагрузку, которую можешь контролировать."
        return HStack(alignment: .top, spacing: 13) {
            Image(systemName: "lightbulb.fill").foregroundStyle(.yellow).font(.title3)
            VStack(alignment: .leading, spacing: 5) { Text("СОВЕТ НА СЕГОДНЯ").font(.caption.bold()).tracking(1.2).foregroundStyle(.yellow); Text(advice).font(.caption).foregroundStyle(.white.opacity(0.78)).fixedSize(horizontal: false, vertical: true) }
            Spacer()
        }.padding(17).background(.yellow.opacity(0.11), in: RoundedRectangle(cornerRadius: 20))
    }

    private func finishWorkout() {
        let duration = max(seconds / 60, 1)
        let workout = Workout(type: selectedType, duration: duration, calories: calories)
        workouts.append(workout)
        health.save(workout: workout, startedAt: startedAt, distanceMeters: locationManager.totalDistance)
        locationManager.stop()
        liveActivity.end(elapsedSeconds: seconds, distanceMeters: locationManager.totalDistance)
        seconds = 0; isRunning = false; showFinishState = true
    }

    private var routeCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("МАРШРУТ БЕГА").font(.caption.weight(.bold)).tracking(1.4).foregroundStyle(.mint)
                    Text(locationManager.isTracking ? "GPS записывает путь" : "Нажми «Начать», чтобы записать маршрут")
                        .font(.caption).foregroundStyle(.white.opacity(0.64))
                }
                Spacer()
                Text(locationManager.distanceText).font(.title3.bold()).foregroundStyle(.white)
            }
            Map(position: $mapPosition) {
                if locationManager.route.count > 1 {
                    MapPolyline(coordinates: locationManager.route).stroke(.cyan, lineWidth: 5)
                }
                if let coordinate = locationManager.route.last {
                    Annotation("Вы", coordinate: coordinate, anchor: .center) {
                        Image(systemName: "figure.run.circle.fill").font(.title).foregroundStyle(.mint)
                            .background(.black.opacity(0.35), in: Circle())
                    }
                }
            }
            .mapStyle(.standard(elevation: .flat))
            .frame(height: 210)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .onChange(of: locationManager.route.count) { _, _ in
                if let region = locationManager.routeRegion { mapPosition = .region(region) }
            }
        }
        .padding(18).background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 24))
    }

    private func resumeWorkout() {
        if seconds == 0 {
            startedAt = .now
            showFinishState = false
            locationManager.reset()
            liveActivity.start(workoutName: selectedType.rawValue, startedAt: startedAt)
        }
        isRunning = true
        locationManager.start()
        syncLiveActivity()
    }

    private func pauseWorkout() {
        isRunning = false
        locationManager.stop()
        syncLiveActivity()
    }

    private func resetWorkout() {
        seconds = 0
        isRunning = false
        showFinishState = false
        locationManager.reset()
        liveActivity.end(elapsedSeconds: 0, distanceMeters: 0)
    }

    private func syncLiveActivity() {
        liveActivity.update(
            isRunning: isRunning,
            startedAt: Date.now.addingTimeInterval(-TimeInterval(seconds)),
            elapsedSeconds: seconds,
            distanceMeters: locationManager.totalDistance
        )
    }

    private func applyLockScreenControl() {
        guard let shouldRun = WorkoutControlStore.consumeRequestedRunning() else { return }
        if shouldRun, !isRunning { resumeWorkout() }
        if !shouldRun, isRunning { pauseWorkout() }
    }

    private var weeklyCard: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack { Text("НЕДЕЛЬ В РИТМЕ").font(.caption.weight(.bold)).tracking(1.5); Spacer(); Text("\(weeklyMinutes) / \(weeklyGoalMinutes) мин").font(.headline) }
                .foregroundStyle(.white)
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(Array(weekdayMinutes.enumerated()), id: \.offset) { _, minutes in
                    let value = max(Double(minutes) / Double(max(goalMinutes, 1)), 0.08)
                    Capsule().fill(LinearGradient(colors: [.cyan, .blue], startPoint: .bottom, endPoint: .top))
                        .frame(maxWidth: .infinity).frame(height: min(70 * value + 12, 82))
                }
            }.frame(height: 90)
            HStack { Text("Пн"); Spacer(); Text("Вт"); Spacer(); Text("Ср"); Spacer(); Text("Чт"); Spacer(); Text("Пт"); Spacer(); Text("Сб"); Spacer(); Text("Вс") }
                .font(.caption2).foregroundStyle(.white.opacity(0.45))
            Text(weeklyRemaining == 0 ? "Недельная цель выполнена — отличная работа!" : "До недельной цели осталось \(weeklyRemaining) мин")
                .font(.caption).foregroundStyle(.cyan)
        }
        .padding(20).background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 24))
    }

    private var weightPlan: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("ПЛАН ПО ВЕСУ").font(.caption.weight(.bold)).tracking(1.5).foregroundStyle(.cyan)
                    Text("Твоя цель").font(.title3.bold()).foregroundStyle(.white)
                }
                Spacer()
                Image(systemName: "scale.3d").font(.title2).foregroundStyle(.cyan)
                    .frame(width: 44, height: 44).background(.cyan.opacity(0.14), in: Circle())
            }
            HStack(spacing: 10) {
                WeightField(title: "Сейчас", value: $currentWeight)
                WeightField(title: "Цель", value: $targetWeight)
                WeightField(title: "Рост", value: $height, unit: "см")
            }
            Divider().overlay(.white.opacity(0.15))
            HStack(spacing: 12) {
                PlanStat(value: String(format: "−%.1f", personalGoal), caption: "кг до цели", tint: .orange)
                PlanStat(value: "\(planWeeks)", caption: "недель план", tint: .cyan)
                PlanStat(value: String(format: "%.1f", bmi), caption: "ИМТ", tint: .purple)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Ориентировочная норма веса: \(bodyNorm.healthyRange). Базовая норма энергии: около \(bodyNorm.basalCalories) ккал/день.")
                    .font(.caption.weight(.semibold)).foregroundStyle(.white)
                Text(recommendedLoss > 0 ? "По росту и весу можно снизить примерно \(String(format: "%.1f", recommendedLoss)) кг до верхней границы здорового ИМТ." : "Ваш текущий вес находится в диапазоне здорового ИМТ.")
                    .font(.caption).foregroundStyle(.white.opacity(0.73)).fixedSize(horizontal: false, vertical: true)
                Text("Безопасный темп: около 0,5 кг в неделю.").font(.caption2.weight(.medium)).foregroundStyle(.cyan)
            }
        }
        .padding(20).background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 24))
    }
}

private struct WorkoutMascotView: View {
    let type: WorkoutType
    let isRunning: Bool
    let isTired: Bool
    @State private var moving = false

    private var assetName: String {
        if type == .cycling { return isTired ? "FoxCyclingTired" : "FoxCycling" }
        return isTired ? "FoxRunningTired" : "FoxRunning"
    }

    var body: some View {
        Image(assetName)
            .resizable()
            .scaledToFit()
            .scaleEffect(isTired ? 0.88 : 1)
            .offset(x: isRunning && moving ? 5 : isRunning ? -5 : 0, y: isRunning && moving ? -4 : isTired ? 5 : 0)
            .rotationEffect(.degrees(isTired ? 3 : isRunning && moving ? 1.2 : -1.2))
            .onAppear { moving = isRunning }
            .onChange(of: isRunning) { _, active in moving = active }
            .animation(
                isRunning
                    ? .easeInOut(duration: type == .cycling ? 0.28 : 0.18).repeatForever(autoreverses: true)
                    : .easeOut(duration: 0.25),
                value: moving
            )
            .accessibilityLabel(isTired ? "Лисёнок отдыхает после тренировки" : type == .cycling ? "Лисёнок едет на велосипеде" : "Лисёнок быстро бежит")
    }
}

private struct WorkoutPickerView: View {
    @Environment(\.dismiss) private var dismiss
    let onChoose: (WorkoutTemplate) -> Void
    var body: some View {
        NavigationStack {
            List(WorkoutTemplate.all) { item in
                Button { onChoose(item); dismiss() } label: {
                    HStack(spacing: 14) { Image(systemName: item.type.symbol).font(.title3).foregroundStyle(.white).frame(width: 42, height: 42).background(item.type.color, in: Circle()); VStack(alignment: .leading) { Text(item.title).fontWeight(.semibold); Text("\(item.minutes) мин · \(item.subtitle)").font(.caption).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "chevron.right").foregroundStyle(.tertiary) }
                }.foregroundStyle(.primary)
            }.navigationTitle("Выбери тренировку").toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Готово") { dismiss() } } }
        }
    }
}

private struct GoalSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var sessionMinutes: Int
    @Binding var weeklyMinutes: Int
    let onSave: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Одна тренировка") {
                    Stepper("Длительность: \(sessionMinutes) мин", value: $sessionMinutes, in: 5...120, step: 5)
                    Text("Это время автоматически подставляется в таймер следующей тренировки.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Цель на неделю") {
                    Stepper("Всего: \(weeklyMinutes) мин", value: $weeklyMinutes, in: 30...900, step: 15)
                    Text("Сохранённые тренировки за текущую неделю суммируются в этой цели.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Настроить цели")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { onSave(); dismiss() }
                }
            }
        }
    }
}

private struct RegistrationView: View {
    @AppStorage("profileComplete") private var profileComplete = false
    @AppStorage("userName") private var savedName = ""
    @AppStorage("userAge") private var savedAge = 25
    @AppStorage("userGender") private var savedGender = Gender.unspecified.rawValue
    @AppStorage("currentWeight") private var savedWeight = 84.0
    @AppStorage("height") private var savedHeight = 178.0
    @State private var name = ""
    @State private var age = 25
    @State private var gender: Gender = .unspecified
    @State private var weight = 84.0
    @State private var height = 178.0

    private var canContinue: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (13...120).contains(age) && weight > 25 && height > 100 }
    private var bodyNorm: BodyNorm { BodyNorm(weight: weight, height: height, age: age, gender: gender) }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.04, green: 0.06, blue: 0.14), Color(red: 0.10, green: 0.08, blue: 0.24)], startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 23) {
                    Spacer(minLength: 38)
                    Image(systemName: "figure.run.circle.fill").font(.system(size: 66)).foregroundStyle(.cyan)
                    Text("Давай познакомимся").font(.largeTitle.bold()).foregroundStyle(.white)
                    Text("Заполни профиль один раз — так приложение сможет составить твой план тренировок и веса.").foregroundStyle(.white.opacity(0.65))
                    VStack(spacing: 14) {
                        ProfileTextField(title: "Как тебя зовут?", text: $name)
                        HStack(spacing: 14) {
                            ProfileNumberField(title: "Возраст", value: $age, unit: "лет")
                            ProfileDoubleField(title: "Рост", value: $height, unit: "см")
                        }
                        ProfileDoubleField(title: "Текущий вес", value: $weight, unit: "кг")
                        VStack(alignment: .leading, spacing: 9) {
                            Text("Пол").font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.6))
                            Picker("Пол", selection: $gender) { ForEach(Gender.allCases) { Text($0.rawValue).tag($0) } }
                                .pickerStyle(.segmented)
                        }
                    }.padding(18).background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 24))
                    VStack(alignment: .leading, spacing: 10) {
                        Text("ТВОИ ОРИЕНТИРЫ").font(.caption.weight(.bold)).tracking(1.3).foregroundStyle(.cyan)
                        HStack(spacing: 12) {
                            OnboardingStat(value: bodyNorm.healthyRange, caption: "здоровый диапазон веса")
                            OnboardingStat(value: "\(bodyNorm.basalCalories) ккал", caption: "базовая норма в день")
                        }
                        Text("Расчёты основаны на росте, весе, возрасте и поле; они ориентировочные и не заменяют консультацию врача.").font(.caption).foregroundStyle(.white.opacity(0.52))
                    }.padding(17).background(.cyan.opacity(0.09), in: RoundedRectangle(cornerRadius: 20))
                    Button("Создать мой план") {
                        savedName = name.trimmingCharacters(in: .whitespacesAndNewlines); savedAge = age; savedGender = gender.rawValue; savedWeight = weight; savedHeight = height; profileComplete = true
                    }
                    .font(.headline).foregroundStyle(.black).frame(maxWidth: .infinity).padding(.vertical, 17).background(canContinue ? .white : .white.opacity(0.35), in: Capsule()).disabled(!canContinue)
                }.padding(24)
            }
        }
    }
}

private struct OnboardingStat: View {
    let value: String; let caption: String
    var body: some View { VStack(alignment: .leading, spacing: 4) { Text(value).font(.headline.bold()).foregroundStyle(.white); Text(caption).font(.caption2).foregroundStyle(.white.opacity(0.6)).fixedSize(horizontal: false, vertical: true) }.frame(maxWidth: .infinity, alignment: .leading) }
}

private struct ProfileTextField: View {
    let title: String; @Binding var text: String
    var body: some View { VStack(alignment: .leading, spacing: 7) { Text(title).font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.6)); TextField("Имя", text: $text).textInputAutocapitalization(.words).padding(13).foregroundStyle(.white).background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 13)) } }
}

private struct ProfileNumberField: View {
    let title: String; @Binding var value: Int; let unit: String
    var body: some View { VStack(alignment: .leading, spacing: 7) { Text(title).font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.6)); HStack { TextField("0", value: $value, format: .number).keyboardType(.numberPad).foregroundStyle(.white); Text(unit).font(.caption).foregroundStyle(.white.opacity(0.5)) }.padding(13).background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 13)) }.frame(maxWidth: .infinity) }
}

private struct ProfileDoubleField: View {
    let title: String; @Binding var value: Double; let unit: String
    var body: some View { VStack(alignment: .leading, spacing: 7) { Text(title).font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.6)); HStack { TextField("0", value: $value, format: .number.precision(.fractionLength(1))).keyboardType(.decimalPad).foregroundStyle(.white); Text(unit).font(.caption).foregroundStyle(.white.opacity(0.5)) }.padding(13).background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 13)) } }
}

private struct WeightField: View {
    let title: String
    @Binding var value: Double
    var unit: String = "кг"
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption2).foregroundStyle(.white.opacity(0.55))
            HStack(spacing: 3) {
                TextField("0", value: $value, format: .number.precision(.fractionLength(1)))
                    .keyboardType(.decimalPad).font(.headline.monospacedDigit()).foregroundStyle(.white).frame(minWidth: 0)
                Text(unit).font(.caption2).foregroundStyle(.white.opacity(0.55))
            }
            .padding(.horizontal, 10).padding(.vertical, 11).background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
        }.frame(maxWidth: .infinity)
    }
}

private struct PlanStat: View {
    let value: String; let caption: String; let tint: Color
    var body: some View {
        VStack(spacing: 3) {
            Text(value).font(.title3.bold()).foregroundStyle(tint)
            Text(caption).font(.caption2).foregroundStyle(.white.opacity(0.55))
        }.frame(maxWidth: .infinity).padding(.vertical, 9).background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct MetricCard: View {
    let value: String; let title: String; let icon: String; let color: Color
    var body: some View { HStack(spacing: 12) { Image(systemName: icon).foregroundStyle(color).font(.title3).frame(width: 34, height: 34).background(color.opacity(0.16), in: Circle()); VStack(alignment: .leading) { Text(value).font(.title3.bold()); Text(title).font(.caption2).foregroundStyle(.white.opacity(0.55)) }; Spacer() }.foregroundStyle(.white).padding(15).frame(maxWidth: .infinity).background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 20)) }
}

private struct HistoryView: View {
    @Environment(\.dismiss) private var dismiss
    let workouts: [Workout]
    var body: some View { NavigationStack { List(workouts) { workout in HStack { Image(systemName: workout.type.symbol).foregroundStyle(workout.type.color).frame(width: 30); VStack(alignment: .leading) { Text(workout.type.rawValue).fontWeight(.semibold); Text(workout.date, format: .dateTime.day().month()).font(.caption).foregroundStyle(.secondary) }; Spacer(); Text("\(workout.duration) мин") } }.navigationTitle("История").toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Готово") { dismiss() } } } } }
}

#Preview { ContentView() }
