import SwiftUI
import HealthKit
import MapKit
import CoreLocation
import ActivityKit
import CloudKit
import UIKit

@main
struct SportTrackerApp: App {
    init() {
        let scrollViewAppearance = UIScrollView.appearance()
        scrollViewAppearance.bounces = false
        scrollViewAppearance.alwaysBounceVertical = false
        scrollViewAppearance.alwaysBounceHorizontal = false
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
        }
    }
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

enum Mascot: String, CaseIterable, Identifiable {
    case fox, cat, dog, bunny

    var id: String { rawValue }
    var title: String {
        switch self {
        case .fox: "Лисёнок"
        case .cat: "Котик"
        case .dog: "Щенок"
        case .bunny: "Кролик"
        }
    }
    var emoji: String {
        switch self {
        case .fox: "🦊"
        case .cat: "🐱"
        case .dog: "🐶"
        case .bunny: "🐰"
        }
    }
    var previewAssetName: String {
        switch self {
        case .fox: "FoxRunning"
        case .cat: "CatRunning"
        case .dog: "DogRunning"
        case .bunny: "BunnyRunning"
        }
    }
    var tint: Color {
        switch self {
        case .fox: .orange
        case .cat: .purple
        case .dog: .cyan
        case .bunny: .pink
        }
    }
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
    @State private var workouts: [Workout] = []
    @State private var selectedType: WorkoutType = .running
    @State private var seconds = 0
    @State private var isRunning = false
    @State private var goalMinutes = 30
    @State private var showHistory = false
    @State private var showTemplates = false
    @State private var showGoals = false
    @State private var showFinishState = false
    @State private var showLogoutAlert = false
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
    @AppStorage("selectedMascot") private var storedMascot = Mascot.fox.rawValue
    @AppStorage("profileComplete") private var profileComplete = false
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
    private var mascot: Mascot { Mascot(rawValue: storedMascot) ?? .fox }

    var body: some View {
        TabView {
            dashboard
                .tabItem { Label("Тренировка", systemImage: "figure.run") }
            RecipesView()
                .tabItem { Label("Питание", systemImage: "fork.knife") }
            CommunityChatView()
                .tabItem { Label("Чат", systemImage: "message.fill") }
        }
        .tint(.cyan)
    }

    private var dashboard: some View {
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
            .alert("Выйти из профиля?", isPresented: $showLogoutAlert) {
                Button("Выйти", role: .destructive) { logOut() }
                Button("Отмена", role: .cancel) { }
            } message: {
                Text("Данные профиля на этом устройстве будут сброшены. Ты вернёшься к начальному экрану выбора зверюшки.")
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
            VStack(spacing: 1) {
                Image(mascot.previewAssetName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 31, height: 31)
                Text(mascot.title).font(.caption2.weight(.semibold)).foregroundStyle(.white.opacity(0.7))
            }
            Button { showLogoutAlert = true } label: {
                Image(systemName: "rectangle.portrait.and.arrow.right").font(.title3.bold()).foregroundStyle(.white)
                    .frame(width: 46, height: 46).background(.white.opacity(0.12), in: Circle())
            }
            .accessibilityLabel("Выйти из профиля")
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
                    WorkoutMascotView(mascot: mascot, type: selectedType, isRunning: isRunning, isTired: mascotIsTired)
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

    private func logOut() {
        locationManager.stop()
        liveActivity.end(elapsedSeconds: seconds, distanceMeters: locationManager.totalDistance)
        userName = ""
        userAge = 25
        storedGender = Gender.unspecified.rawValue
        currentWeight = 84
        targetWeight = 72
        height = 178
        storedMascot = Mascot.fox.rawValue
        preferredSessionMinutes = 30
        weeklyGoalMinutes = 180
        profileComplete = false
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

private enum RecipeCategory: String, CaseIterable, Identifiable {
    case breakfast = "Завтраки", lunch = "Обеды", dinner = "Ужины", snack = "Перекусы", dessert = "Десерты"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .breakfast: "sunrise.fill"
        case .lunch: "fork.knife"
        case .dinner: "moon.stars.fill"
        case .snack: "leaf.fill"
        case .dessert: "heart.fill"
        }
    }
    var tint: Color {
        switch self {
        case .breakfast: .orange
        case .lunch: .cyan
        case .dinner: .purple
        case .snack: .mint
        case .dessert: .pink
        }
    }
    var imageName: String {
        switch self {
        case .breakfast: "RecipeBreakfast"
        case .lunch: "RecipeLunch"
        case .dinner: "RecipeSnack"
        case .snack: "RecipeDinner"
        case .dessert: "RecipeDessert"
        }
    }
}

private struct Recipe: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let category: RecipeCategory
    let calories: Int
    let protein: Int
    let fat: Int
    let carbs: Int
    let duration: Int
    let symbol: String
    let ingredients: [String]
    let steps: [String]

    private var searchIndex: String {
        ([title, subtitle, category.rawValue] + ingredients + [
            "\(calories) ккал", "\(protein) г белка", "\(fat) г жиров", "\(carbs) г углеводов"
        ]).joined(separator: " ")
    }

    func matches(_ query: String) -> Bool {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalizedQuery.isEmpty || searchIndex.localizedStandardContains(normalizedQuery)
    }
}

private enum RecipeLibrary {
    static let all: [Recipe] = [
        Recipe(title: "Овсянка с ягодами", subtitle: "Тёплый завтрак для энергии", category: .breakfast, calories: 365, protein: 15, fat: 9, carbs: 56, duration: 10, symbol: "bowl.fill", ingredients: ["Овсяные хлопья — 60 г", "Молоко или растительный напиток — 180 мл", "Греческий йогурт — 80 г", "Ягоды — 100 г", "Семена чиа — 1 ч. л."], steps: ["Свари овсянку в молоке до мягкости.", "Переложи в тарелку и добавь йогурт.", "Укрась ягодами и семенами чиа."]),
        Recipe(title: "Омлет с овощами", subtitle: "Сытно и много белка", category: .breakfast, calories: 298, protein: 23, fat: 19, carbs: 10, duration: 12, symbol: "sun.max.fill", ingredients: ["Яйца — 2 шт.", "Белки — 2 шт.", "Томаты черри — 100 г", "Шпинат — горсть", "Сыр — 25 г", "Оливковое масло — 1 ч. л."], steps: ["Взбей яйца и белки с щепоткой соли.", "Обжарь томаты и шпинат на масле 2 минуты.", "Влей яйца, добавь сыр и готовь под крышкой."]),
        Recipe(title: "Творожные панкейки", subtitle: "Нежный фитнес-завтрак", category: .breakfast, calories: 342, protein: 29, fat: 10, carbs: 35, duration: 18, symbol: "flame.fill", ingredients: ["Творог 5% — 180 г", "Яйцо — 1 шт.", "Овсяная мука — 35 г", "Банан — ½ шт.", "Разрыхлитель — ½ ч. л."], steps: ["Разомни банан и смешай все ингредиенты.", "Сформируй небольшие панкейки.", "Обжарь на сухой сковороде по 2–3 минуты с каждой стороны."]),
        Recipe(title: "Йогурт с гранолой", subtitle: "Быстрый вариант без готовки", category: .breakfast, calories: 319, protein: 20, fat: 11, carbs: 37, duration: 5, symbol: "cup.and.saucer.fill", ingredients: ["Греческий йогурт — 200 г", "Гранола без сахара — 35 г", "Киви — 1 шт.", "Мёд — 1 ч. л.", "Тыквенные семечки — 10 г"], steps: ["Нарежь киви.", "Выложи йогурт в миску.", "Добавь гранолу, киви, семечки и мёд."]),
        Recipe(title: "Куриный боул", subtitle: "Рис, курица и свежие овощи", category: .lunch, calories: 486, protein: 42, fat: 14, carbs: 51, duration: 25, symbol: "takeoutbag.and.cup.and.straw.fill", ingredients: ["Куриное филе — 150 г", "Рис басмати, готовый — 140 г", "Огурец — 100 г", "Морковь — 70 г", "Авокадо — 40 г", "Соевый соус — 1 ст. л."], steps: ["Обжарь или запеки курицу до готовности.", "Нарежь овощи тонкой соломкой.", "Собери в миске рис, курицу и овощи, добавь соус."]),
        Recipe(title: "Лосось с гречкой", subtitle: "Омега-3 и сложные углеводы", category: .lunch, calories: 522, protein: 36, fat: 24, carbs: 40, duration: 30, symbol: "fish.fill", ingredients: ["Филе лосося — 140 г", "Гречка, готовая — 150 г", "Брокколи — 150 г", "Лимон — ¼ шт.", "Оливковое масло — 1 ч. л."], steps: ["Запеки лосось 15–18 минут при 190°C.", "Отвари брокколи до мягкости.", "Подай с гречкой, лимоном и каплей масла."]),
        Recipe(title: "Паста с индейкой", subtitle: "Белковый обед после тренировки", category: .lunch, calories: 508, protein: 40, fat: 13, carbs: 59, duration: 25, symbol: "fork.knife.circle.fill", ingredients: ["Филе индейки — 150 г", "Цельнозерновая паста, готовая — 160 г", "Томатное пюре — 120 г", "Цукини — 120 г", "Пармезан — 10 г"], steps: ["Отвари пасту до состояния al dente.", "Обжарь индейку и цукини.", "Добавь томатное пюре, смешай с пастой и посыпь сыром."]),
        Recipe(title: "Суп из чечевицы", subtitle: "Растительный белок и клетчатка", category: .lunch, calories: 332, protein: 18, fat: 8, carbs: 48, duration: 35, symbol: "carrot.fill", ingredients: ["Красная чечевица — 70 г", "Морковь — 1 шт.", "Лук — ½ шт.", "Томаты в собственном соку — 150 г", "Овощной бульон — 400 мл", "Йогурт для подачи — 30 г"], steps: ["Обжарь лук и морковь 3 минуты.", "Добавь чечевицу, томаты и бульон.", "Вари 20 минут, при подаче добавь йогурт."]),
        Recipe(title: "Тёплый салат с нутом", subtitle: "Яркий и сытный вегетарианский ужин", category: .dinner, calories: 394, protein: 17, fat: 17, carbs: 45, duration: 20, symbol: "leaf.circle.fill", ingredients: ["Нут, готовый — 160 г", "Тыква — 180 г", "Руккола — 40 г", "Фета — 35 г", "Оливковое масло — 1 ч. л.", "Паприка и лимонный сок"], steps: ["Запеки кубики тыквы с паприкой 15 минут.", "Прогрей нут на сковороде.", "Смешай с рукколой, тыквой и фетой, добавь лимонный сок."]),
        Recipe(title: "Тофу стир-фрай", subtitle: "Овощи в азиатском стиле", category: .dinner, calories: 418, protein: 25, fat: 18, carbs: 41, duration: 20, symbol: "flame.circle.fill", ingredients: ["Тофу — 180 г", "Смесь овощей — 250 г", "Лапша соба, готовая — 120 г", "Соевый соус — 1 ст. л.", "Кунжут — 1 ч. л."], steps: ["Обсуши и обжарь кубики тофу до корочки.", "Добавь овощи и готовь 5–7 минут.", "Смешай с лапшой, соусом и кунжутом."]),
        Recipe(title: "Тунец с картофелем", subtitle: "Простой ужин за 15 минут", category: .dinner, calories: 447, protein: 35, fat: 13, carbs: 49, duration: 15, symbol: "circle.grid.cross.fill", ingredients: ["Тунец в собственном соку — 120 г", "Молодой картофель — 220 г", "Стручковая фасоль — 150 г", "Яйцо — 1 шт.", "Йогуртовый соус — 40 г"], steps: ["Отвари картофель и фасоль.", "Свари яйцо вкрутую.", "Собери тарелку с тунцом и добавь йогуртовый соус."]),
        Recipe(title: "Кесадилья с курицей", subtitle: "Хрустящий ужин без лишнего масла", category: .dinner, calories: 464, protein: 38, fat: 15, carbs: 45, duration: 18, symbol: "circle.hexagongrid.fill", ingredients: ["Цельнозерновая тортилья — 1 шт.", "Куриное филе — 120 г", "Сыр — 35 г", "Болгарский перец — 80 г", "Сальса — 50 г"], steps: ["Нарежь готовую курицу и перец.", "Выложи начинку на половину тортильи, добавь сыр.", "Сложи и обжарь на сухой сковороде с обеих сторон."]),
        Recipe(title: "Яблоко с творогом", subtitle: "Сладкий перекус с белком", category: .snack, calories: 214, protein: 18, fat: 6, carbs: 24, duration: 5, symbol: "apple.logo", ingredients: ["Яблоко — 1 шт.", "Творог 5% — 130 г", "Корица — по вкусу", "Грецкие орехи — 8 г"], steps: ["Нарежь яблоко дольками.", "Выложи рядом творог.", "Посыпь корицей и рублеными орехами."]),
        Recipe(title: "Хумус с овощами", subtitle: "Хрустящий перекус на работу", category: .snack, calories: 236, protein: 8, fat: 13, carbs: 24, duration: 7, symbol: "takeoutbag.and.cup.and.straw", ingredients: ["Хумус — 70 г", "Морковь — 100 г", "Огурец — 100 г", "Цельнозерновые хлебцы — 2 шт."], steps: ["Нарежь овощи длинными палочками.", "Переложи хумус в небольшой контейнер.", "Ешь овощи и хлебцы, макая в хумус."]),
        Recipe(title: "Банановый какао-мусс", subtitle: "Десерт без добавленного сахара", category: .dessert, calories: 248, protein: 10, fat: 9, carbs: 35, duration: 8, symbol: "birthday.cake.fill", ingredients: ["Банан — 1 шт.", "Греческий йогурт — 120 г", "Какао — 1 ст. л.", "Арахисовая паста — 1 ч. л."], steps: ["Измельчи банан в блендере.", "Добавь йогурт и какао, взбей до кремовой текстуры.", "Укрась арахисовой пастой и охлади 10 минут."]),
        Recipe(title: "Энергетические шарики", subtitle: "Финики, овсянка и орехи", category: .dessert, calories: 196, protein: 5, fat: 9, carbs: 27, duration: 15, symbol: "sparkles", ingredients: ["Финики без косточек — 70 г", "Овсяные хлопья — 30 г", "Миндаль — 20 г", "Кокосовая стружка — 10 г", "Щепотка соли"], steps: ["Измельчи финики, овсянку и миндаль в блендере.", "Скатай 5–6 небольших шариков.", "Обваляй в кокосовой стружке и охлади."]),

        // Завтраки
        Recipe(title: "Мюсли с яблоком", subtitle: "Овёс, орехи и клетчатка", category: .breakfast, calories: 323, protein: 10, fat: 12, carbs: 51, duration: 5, symbol: "bowl.fill", ingredients: ["Овсяные хлопья — 45 г", "Яблоко — 1 шт.", "Молоко или йогурт — 180 мл", "Грецкие орехи — 15 г", "Семечки — 10 г", "Корица — по вкусу"], steps: ["Смешай овсянку, семечки и орехи.", "Добавь нарезанное яблоко и корицу.", "Залей молоком или йогуртом и подавай."]),
        Recipe(title: "Яичные маффины с индейкой", subtitle: "Заготовка на несколько завтраков", category: .breakfast, calories: 265, protein: 25, fat: 15, carbs: 8, duration: 25, symbol: "cupcake.fill", ingredients: ["Яйца — 2 шт.", "Филе индейки — 70 г", "Шампиньоны — 80 г", "Шпинат — горсть", "Сыр — 20 г"], steps: ["Нарежь индейку и грибы, слегка обжарь.", "Взбей яйца, смешай с начинкой и разлей по формочкам.", "Запекай 15–18 минут при 180°C."]),
        Recipe(title: "Тост с авокадо и яйцом", subtitle: "Цельнозерновой завтрак за 10 минут", category: .breakfast, calories: 339, protein: 16, fat: 20, carbs: 27, duration: 10, symbol: "avocado", ingredients: ["Цельнозерновой хлеб — 2 ломтика", "Авокадо — ½ шт.", "Яйцо — 1 шт.", "Томаты черри — 80 г", "Лимонный сок и перец"], steps: ["Подсуши хлеб на сухой сковороде или в тостере.", "Разомни авокадо с лимонным соком и перцем.", "Намажь тосты, добавь яйцо и томаты."]),
        Recipe(title: "Зелёный смузи", subtitle: "Банан, ягоды и шпинат", category: .breakfast, calories: 284, protein: 18, fat: 6, carbs: 43, duration: 5, symbol: "cup.and.saucer.fill", ingredients: ["Банан — 1 шт.", "Замороженные ягоды — 100 г", "Шпинат — горсть", "Греческий йогурт — 150 г", "Вода или молоко — 120 мл"], steps: ["Положи все ингредиенты в чашу блендера.", "Взбей до однородной текстуры.", "При необходимости добавь немного воды."]),
        Recipe(title: "Кесадилья с яйцом и фасолью", subtitle: "Плотный завтрак с растительным белком", category: .breakfast, calories: 385, protein: 22, fat: 14, carbs: 45, duration: 15, symbol: "circle.hexagongrid.fill", ingredients: ["Цельнозерновая тортилья — 1 шт.", "Яйца — 2 шт.", "Чёрная фасоль — 70 г", "Томат — 1 шт.", "Сыр — 25 г"], steps: ["Прогрей фасоль с нарезанным томатом.", "Приготовь скрэмбл из яиц.", "Выложи начинку и сыр на тортилью, сложи и подрумянь."]),
        Recipe(title: "Творожный боул с чиа", subtitle: "Белковый завтрак без готовки", category: .breakfast, calories: 310, protein: 28, fat: 12, carbs: 27, duration: 5, symbol: "leaf.circle.fill", ingredients: ["Творог 5% — 180 г", "Ягоды — 100 г", "Семена чиа — 1 ч. л.", "Миндаль — 12 г", "Мёд — 1 ч. л."], steps: ["Выложи творог в глубокую миску.", "Добавь ягоды, чиа и рубленый миндаль.", "По желанию добавь немного мёда."]),

        // Обеды
        Recipe(title: "Паста с курицей, фасолью и шпинатом", subtitle: "Сытный обед с белком и клетчаткой", category: .lunch, calories: 519, protein: 39, fat: 12, carbs: 66, duration: 25, symbol: "fork.knife.circle.fill", ingredients: ["Цельнозерновая паста, готовая — 180 г", "Куриное филе — 120 г", "Белая фасоль — 100 г", "Шпинат — 80 г", "Томатный соус — 100 г", "Пармезан — 10 г"], steps: ["Отвари пасту и сохрани немного воды от варки.", "Обжарь курицу, добавь фасоль, шпинат и томатный соус.", "Смешай с пастой, при необходимости добавь воду и посыпь сыром."]),
        Recipe(title: "Киноа-салат с нутом", subtitle: "Свежий обед в контейнер", category: .lunch, calories: 442, protein: 17, fat: 17, carbs: 57, duration: 20, symbol: "leaf.fill", ingredients: ["Киноа, готовая — 160 г", "Нут, готовый — 120 г", "Огурец — 100 г", "Томаты — 120 г", "Петрушка — горсть", "Оливковое масло — 1 ч. л.", "Лимонный сок"], steps: ["Приготовь киноа и дай ей немного остыть.", "Нарежь овощи и зелень.", "Смешай все ингредиенты с лимонным соком и маслом."]),
        Recipe(title: "Пита с тунцом и авокадо", subtitle: "Быстрый вариант без плиты", category: .lunch, calories: 416, protein: 31, fat: 16, carbs: 39, duration: 10, symbol: "takeoutbag.and.cup.and.straw.fill", ingredients: ["Цельнозерновая пита — 1 шт.", "Тунец в собственном соку — 120 г", "Авокадо — 50 г", "Греческий йогурт — 30 г", "Огурец — 80 г", "Листья салата"], steps: ["Разомни авокадо и смешай с тунцом и йогуртом.", "Нарежь огурец.", "Наполни питу салатом, огурцом и тунцовой смесью."]),
        Recipe(title: "Буррито-боул с курицей", subtitle: "Рис, кукуруза и чёрная фасоль", category: .lunch, calories: 535, protein: 43, fat: 14, carbs: 61, duration: 25, symbol: "takeoutbag.and.cup.and.straw.fill", ingredients: ["Куриное филе — 150 г", "Рис, готовый — 140 г", "Чёрная фасоль — 100 г", "Кукуруза — 70 г", "Томаты — 100 г", "Йогурт — 40 г", "Лайм"], steps: ["Приправь и обжарь куриное филе.", "Прогрей фасоль и кукурузу.", "Собери в миске рис, курицу, овощи и йогурт с соком лайма."]),
        Recipe(title: "Булгур с запечёнными овощами", subtitle: "Тёплый вегетарианский обед", category: .lunch, calories: 398, protein: 15, fat: 13, carbs: 58, duration: 30, symbol: "carrot.fill", ingredients: ["Булгур, готовый — 180 г", "Кабачок — 150 г", "Болгарский перец — 120 г", "Нут — 100 г", "Фета — 30 г", "Оливковое масло — 1 ч. л."], steps: ["Нарежь овощи, смешай с нутом и запекай 20 минут при 200°C.", "Приготовь булгур по инструкции.", "Смешай булгур с овощами и раскроши сверху фету."]),
        Recipe(title: "Шакшука с фасолью", subtitle: "Томаты, яйца и пряности", category: .lunch, calories: 364, protein: 22, fat: 15, carbs: 37, duration: 20, symbol: "flame.fill", ingredients: ["Яйца — 2 шт.", "Белая фасоль — 100 г", "Томаты в собственном соку — 200 г", "Лук — ½ шт.", "Сладкий перец — 80 г", "Цельнозерновой хлеб — 1 ломтик"], steps: ["Обжарь лук и перец, добавь томаты и специи.", "Вмешай фасоль и сделай два углубления.", "Разбей яйца, готовь под крышкой и подавай с хлебом."]),

        // Ужины
        Recipe(title: "Курица с цукини и томатами", subtitle: "Лёгкий ужин на одной сковороде", category: .dinner, calories: 368, protein: 42, fat: 14, carbs: 19, duration: 25, symbol: "flame.circle.fill", ingredients: ["Куриное филе — 160 г", "Цукини — 200 г", "Томаты черри — 150 г", "Чеснок — 1 зубчик", "Оливковое масло — 1 ч. л.", "Итальянские травы"], steps: ["Нарежь курицу и обжарь до золотистой корочки.", "Добавь цукини, чеснок и готовь 5 минут.", "Вмешай томаты и травы, прогрей ещё 3–4 минуты."]),
        Recipe(title: "Креветки с овощами и рисом", subtitle: "Быстрый ужин в азиатском стиле", category: .dinner, calories: 424, protein: 34, fat: 10, carbs: 52, duration: 20, symbol: "fish.fill", ingredients: ["Креветки очищенные — 150 г", "Рис, готовый — 150 г", "Брокколи — 150 г", "Морковь — 80 г", "Соевый соус — 1 ст. л.", "Кунжут — 1 ч. л."], steps: ["Обжарь креветки по 1–2 минуты с каждой стороны.", "Добавь овощи и немного воды, готовь до мягкости.", "Смешай с рисом, соевым соусом и кунжутом."]),
        Recipe(title: "Тефтели из индейки с кускусом", subtitle: "Домашний белковый ужин", category: .dinner, calories: 461, protein: 39, fat: 16, carbs: 42, duration: 35, symbol: "fork.knife", ingredients: ["Фарш индейки — 160 г", "Кускус, готовый — 150 г", "Яйцо — 1 шт.", "Томатный соус — 150 г", "Кабачок — 120 г", "Зелень"], steps: ["Смешай фарш с яйцом и зеленью, сформируй тефтели.", "Запекай 20 минут при 190°C или туши в соусе.", "Приготовь кускус и подавай с тефтелями и кабачком."]),
        Recipe(title: "Треска с томатами и картофелем", subtitle: "Рыбный ужин с минимумом масла", category: .dinner, calories: 397, protein: 37, fat: 9, carbs: 43, duration: 30, symbol: "fish.fill", ingredients: ["Филе трески — 170 г", "Картофель — 200 г", "Томаты черри — 150 г", "Стручковая фасоль — 120 г", "Оливковое масло — 1 ч. л.", "Лимон"], steps: ["Нарежь картофель дольками и запекай 15 минут при 200°C.", "Добавь рыбу, томаты и фасоль, сбрызни маслом.", "Запекай ещё 12–15 минут, подавай с лимоном."]),
        Recipe(title: "Фаршированные перцы с индейкой", subtitle: "Рис, овощи и нежный фарш", category: .dinner, calories: 412, protein: 36, fat: 12, carbs: 41, duration: 45, symbol: "bell.fill", ingredients: ["Болгарский перец — 2 шт.", "Фарш индейки — 160 г", "Рис, готовый — 120 г", "Томатное пюре — 180 г", "Лук — ½ шт.", "Сыр — 20 г"], steps: ["Смешай фарш, рис и мелко нарезанный лук.", "Наполни половинки перцев и залей томатным пюре.", "Запекай 30 минут при 190°C, в конце добавь сыр."]),
        Recipe(title: "Батат с чёрной фасолью", subtitle: "Растительный ужин с сальсой", category: .dinner, calories: 409, protein: 16, fat: 12, carbs: 64, duration: 35, symbol: "leaf.circle.fill", ingredients: ["Батат — 250 г", "Чёрная фасоль — 130 г", "Томаты — 100 г", "Авокадо — 40 г", "Йогурт — 30 г", "Паприка и лайм"], steps: ["Наколи батат вилкой и запекай 30 минут при 200°C.", "Прогрей фасоль с паприкой.", "Разрежь батат, добавь фасоль, томаты, авокадо и йогурт."]),

        // Перекусы
        Recipe(title: "Йогурт с тыквенными семечками", subtitle: "Хрустящий перекус с белком", category: .snack, calories: 218, protein: 19, fat: 10, carbs: 15, duration: 3, symbol: "cup.and.saucer.fill", ingredients: ["Греческий йогурт — 170 г", "Тыквенные семечки — 15 г", "Ягоды — 70 г", "Корица"], steps: ["Выложи йогурт в небольшую миску.", "Добавь ягоды и семечки.", "Посыпь корицей перед подачей."]),
        Recipe(title: "Банановый тост с арахисовой пастой", subtitle: "Перекус перед тренировкой", category: .snack, calories: 276, protein: 9, fat: 12, carbs: 37, duration: 5, symbol: "bolt.heart.fill", ingredients: ["Цельнозерновой хлеб — 1 ломтик", "Банан — 1 шт.", "Арахисовая паста — 15 г", "Корица"], steps: ["Подсуши хлеб в тостере.", "Намажь арахисовую пасту.", "Выложи ломтики банана и добавь корицу."]),
        Recipe(title: "Творог с ягодами и какао", subtitle: "Сладко без лишнего сахара", category: .snack, calories: 231, protein: 24, fat: 8, carbs: 19, duration: 5, symbol: "heart.fill", ingredients: ["Творог 5% — 170 г", "Ягоды — 100 г", "Какао — 1 ч. л.", "Мёд — 1 ч. л."], steps: ["Смешай творог с какао.", "Добавь ягоды.", "По желанию подсласти мёдом."]),
        Recipe(title: "Хрустящий нут", subtitle: "Пряный перекус из духовки", category: .snack, calories: 205, protein: 10, fat: 6, carbs: 30, duration: 30, symbol: "flame.fill", ingredients: ["Нут, готовый — 140 г", "Оливковое масло — 1 ч. л.", "Паприка — ½ ч. л.", "Чесночный порошок", "Соль — щепотка"], steps: ["Обсуши нут бумажным полотенцем.", "Смешай с маслом и специями.", "Запекай 20–25 минут при 200°C, один раз перемешай."]),
        Recipe(title: "Орехово-фруктовый микс", subtitle: "Удобно взять с собой", category: .snack, calories: 242, protein: 6, fat: 15, carbs: 24, duration: 2, symbol: "leaf.fill", ingredients: ["Миндаль — 20 г", "Грецкие орехи — 10 г", "Курага без сахара — 25 г", "Тыквенные семечки — 10 г"], steps: ["Отмерь орехи и семечки.", "Нарежь курагу небольшими кусочками.", "Смешай и разложи по контейнеру."]),
        Recipe(title: "Финиковый батончик с овсом", subtitle: "Домашний перекус на неделю", category: .snack, calories: 219, protein: 6, fat: 9, carbs: 33, duration: 20, symbol: "rectangle.portrait.fill", ingredients: ["Финики без косточек — 80 г", "Овсяные хлопья — 45 г", "Арахисовая паста — 20 г", "Семечки — 15 г", "Щепотка соли"], steps: ["Измельчи финики с арахисовой пастой.", "Смешай с овсянкой и семечками.", "Утрамбуй в форму, охлади и нарежь на батончики."]),

        // Десерты
        Recipe(title: "Запечённая груша с рикоттой", subtitle: "Тёплый десерт с белком", category: .dessert, calories: 226, protein: 10, fat: 8, carbs: 31, duration: 25, symbol: "heart.fill", ingredients: ["Груша — 1 крупная", "Рикотта — 70 г", "Грецкие орехи — 10 г", "Корица", "Мёд — 1 ч. л."], steps: ["Разрежь грушу пополам и удали сердцевину.", "Запекай 15 минут при 180°C.", "Наполни рикоттой, добавь орехи, корицу и мёд."]),
        Recipe(title: "Йогуртовый лёд с ягодами", subtitle: "Освежающий десерт из морозилки", category: .dessert, calories: 185, protein: 15, fat: 6, carbs: 20, duration: 10, symbol: "snowflake", ingredients: ["Греческий йогурт — 180 г", "Ягоды — 100 г", "Мёд — 1 ч. л.", "Миндаль — 10 г"], steps: ["Смешай йогурт с мёдом.", "Распредели тонким слоем на пергаменте, добавь ягоды и миндаль.", "Заморозь 2–3 часа и разломи на кусочки."]),
        Recipe(title: "Чиа-пудинг с манго", subtitle: "Десерт, который готовится в холодильнике", category: .dessert, calories: 263, protein: 12, fat: 11, carbs: 31, duration: 10, symbol: "drop.fill", ingredients: ["Семена чиа — 25 г", "Молоко — 180 мл", "Греческий йогурт — 80 г", "Манго — 100 г", "Ваниль"], steps: ["Смешай чиа, молоко, йогурт и ваниль.", "Оставь в холодильнике минимум на 2 часа.", "Перед подачей добавь нарезанное манго."]),
        Recipe(title: "Яблоки с корицей на сковороде", subtitle: "Простой тёплый десерт", category: .dessert, calories: 156, protein: 2, fat: 5, carbs: 29, duration: 15, symbol: "apple.logo", ingredients: ["Яблоки — 2 шт.", "Сливочное масло — 1 ч. л.", "Корица — ½ ч. л.", "Грецкие орехи — 10 г", "Йогурт — 50 г"], steps: ["Нарежь яблоки дольками.", "Прогрей на сковороде с маслом и корицей 8–10 минут.", "Подавай с йогуртом и орехами."]),
        Recipe(title: "Банан в шоколаде", subtitle: "Замороженный десерт заготовкой", category: .dessert, calories: 204, protein: 3, fat: 9, carbs: 31, duration: 15, symbol: "birthday.cake.fill", ingredients: ["Банан — 1 шт.", "Тёмный шоколад 70% — 20 г", "Арахис — 10 г", "Кокосовая стружка — 5 г"], steps: ["Нарежь банан крупными кусочками.", "Окуни в растопленный шоколад.", "Посыпь арахисом и кокосом, затем заморозь."]),
        Recipe(title: "Шоколадный крем из тофу", subtitle: "Нежный веганский десерт", category: .dessert, calories: 238, protein: 13, fat: 12, carbs: 24, duration: 8, symbol: "sparkles", ingredients: ["Шелковый тофу — 150 г", "Какао — 1 ст. л.", "Банан — ½ шт.", "Тёмный шоколад — 15 г", "Ваниль"], steps: ["Растопи шоколад короткими импульсами в микроволновке.", "Взбей тофу, банан, какао, ваниль и шоколад.", "Охлади крем 30 минут перед подачей."]),

        // Ещё 20 вариантов для разнообразного меню
        Recipe(title: "Ночная овсянка с бананом", subtitle: "Завтрак, который готовится с вечера", category: .breakfast, calories: 362, protein: 17, fat: 11, carbs: 52, duration: 5, symbol: "moon.stars.fill", ingredients: ["Овсяные хлопья — 55 г", "Молоко — 160 мл", "Греческий йогурт — 100 г", "Банан — ½ шт.", "Арахисовая паста — 10 г", "Корица"], steps: ["Смешай овсянку, молоко, йогурт и корицу в банке.", "Убери в холодильник минимум на 4 часа.", "Утром добавь банан и арахисовую пасту."]),
        Recipe(title: "Гречка с творогом и яйцом", subtitle: "Несладкий белковый завтрак", category: .breakfast, calories: 347, protein: 27, fat: 13, carbs: 33, duration: 12, symbol: "sunrise.fill", ingredients: ["Гречка, готовая — 150 г", "Творог 5% — 120 г", "Яйцо — 1 шт.", "Огурец — 100 г", "Зелень"], steps: ["Прогрей готовую гречку на сковороде или в микроволновке.", "Свари яйцо или приготовь его пашот.", "Собери тарелку с творогом, огурцом и зеленью."]),
        Recipe(title: "Яичный хаш с бататом", subtitle: "Сытный завтрак с овощами", category: .breakfast, calories: 381, protein: 21, fat: 17, carbs: 38, duration: 25, symbol: "flame.fill", ingredients: ["Батат — 180 г", "Яйца — 2 шт.", "Болгарский перец — 100 г", "Шпинат — горсть", "Оливковое масло — 1 ч. л."], steps: ["Нарежь батат мелкими кубиками и обжарь под крышкой до мягкости.", "Добавь перец и шпинат.", "Сделай два углубления, разбей яйца и готовь до желаемой степени."]),
        Recipe(title: "Банановые вафли с йогуртом", subtitle: "Сладкий завтрак без рафинированного сахара", category: .breakfast, calories: 358, protein: 20, fat: 10, carbs: 49, duration: 20, symbol: "square.grid.2x2.fill", ingredients: ["Банан — 1 шт.", "Яйцо — 1 шт.", "Овсяная мука — 45 г", "Разрыхлитель — ½ ч. л.", "Греческий йогурт — 100 г", "Ягоды — 60 г"], steps: ["Разомни банан, смешай с яйцом, мукой и разрыхлителем.", "Испеки вафли в вафельнице или небольшие оладьи на сковороде.", "Подавай с йогуртом и ягодами."]),

        Recipe(title: "Лосось с киноа и авокадо", subtitle: "Обед с омега-3 и цельным зерном", category: .lunch, calories: 548, protein: 35, fat: 25, carbs: 45, duration: 30, symbol: "fish.fill", ingredients: ["Филе лосося — 140 г", "Киноа, готовая — 150 г", "Авокадо — 50 г", "Огурец — 100 г", "Листья салата", "Лимон"], steps: ["Запеки лосось 15–18 минут при 190°C.", "Приготовь киноа и нарежь овощи.", "Собери боул, добавь авокадо и лимонный сок."]),
        Recipe(title: "Соба с индейкой и овощами", subtitle: "Быстрый обед в азиатском стиле", category: .lunch, calories: 487, protein: 38, fat: 13, carbs: 57, duration: 25, symbol: "fork.knife.circle.fill", ingredients: ["Филе индейки — 140 г", "Лапша соба, готовая — 150 г", "Брокколи — 120 г", "Морковь — 80 г", "Соевый соус — 1 ст. л.", "Кунжут — 1 ч. л."], steps: ["Отвари собу по инструкции.", "Обжарь индейку, добавь брокколи и морковь.", "Смешай с лапшой, соусом и кунжутом."]),
        Recipe(title: "Греческий салат с курицей", subtitle: "Свежий обед с высоким содержанием белка", category: .lunch, calories: 431, protein: 40, fat: 21, carbs: 21, duration: 20, symbol: "leaf.fill", ingredients: ["Куриное филе — 150 г", "Огурец — 120 г", "Томаты — 150 г", "Фета — 40 г", "Оливки — 20 г", "Оливковое масло — 1 ч. л."], steps: ["Обжарь или запеки куриное филе.", "Нарежь огурец и томаты.", "Смешай салат, добавь фету, оливки и нарезанную курицу."]),
        Recipe(title: "Карри из нута и шпината", subtitle: "Ароматный растительный обед", category: .lunch, calories: 452, protein: 17, fat: 14, carbs: 65, duration: 25, symbol: "leaf.circle.fill", ingredients: ["Нут, готовый — 150 г", "Рис, готовый — 130 г", "Кокосовое молоко — 80 мл", "Шпинат — 80 г", "Томаты — 120 г", "Паста карри — 1 ч. л."], steps: ["Прогрей томаты с пастой карри.", "Добавь нут, кокосовое молоко и потуши 8 минут.", "Вмешай шпинат и подавай с рисом."]),

        Recipe(title: "Говядина с бурым рисом", subtitle: "Восстановление после силовой тренировки", category: .dinner, calories: 513, protein: 41, fat: 17, carbs: 49, duration: 25, symbol: "flame.circle.fill", ingredients: ["Постная говядина — 150 г", "Бурый рис, готовый — 150 г", "Брокколи — 150 г", "Болгарский перец — 100 г", "Соевый соус — 1 ст. л."], steps: ["Нарежь говядину тонкими полосками и быстро обжарь.", "Добавь овощи и готовь до мягкости.", "Подавай с бурым рисом и соевым соусом."]),
        Recipe(title: "Лодочки из цукини с индейкой", subtitle: "Запечённый ужин с овощами", category: .dinner, calories: 365, protein: 37, fat: 16, carbs: 20, duration: 35, symbol: "leaf.fill", ingredients: ["Цукини — 2 шт.", "Фарш индейки — 160 г", "Томатное пюре — 120 г", "Лук — ½ шт.", "Сыр — 30 г", "Зелень"], steps: ["Разрежь цукини вдоль и вынь часть мякоти.", "Обжарь фарш с луком, мякотью и томатным пюре.", "Наполни лодочки, посыпь сыром и запекай 20 минут при 190°C."]),
        Recipe(title: "Лосось с брокколи и бататом", subtitle: "Ужин на одном противне", category: .dinner, calories: 495, protein: 36, fat: 22, carbs: 42, duration: 35, symbol: "fish.fill", ingredients: ["Филе лосося — 150 г", "Батат — 180 г", "Брокколи — 180 г", "Оливковое масло — 1 ч. л.", "Паприка", "Лимон"], steps: ["Запекай ломтики батата 15 минут при 200°C.", "Добавь лосось и брокколи, приправь маслом и паприкой.", "Готовь ещё 15 минут, подавай с лимоном."]),
        Recipe(title: "Чечевичное рагу с грибами", subtitle: "Согревающий веганский ужин", category: .dinner, calories: 384, protein: 20, fat: 9, carbs: 56, duration: 35, symbol: "carrot.fill", ingredients: ["Зелёная чечевица — 80 г", "Шампиньоны — 180 г", "Морковь — 1 шт.", "Лук — ½ шт.", "Томаты в собственном соку — 200 г", "Овощной бульон — 250 мл"], steps: ["Обжарь лук, морковь и грибы 5 минут.", "Добавь чечевицу, томаты и бульон.", "Туши под крышкой 25 минут до мягкости чечевицы."]),

        Recipe(title: "Хлебцы с яйцом и авокадо", subtitle: "Сбалансированный перекус за 5 минут", category: .snack, calories: 248, protein: 12, fat: 15, carbs: 20, duration: 5, symbol: "circle.grid.cross.fill", ingredients: ["Цельнозерновые хлебцы — 3 шт.", "Яйцо — 1 шт.", "Авокадо — 40 г", "Томаты черри — 60 г", "Перец"], steps: ["Свари яйцо вкрутую.", "Разомни авокадо с перцем.", "Намажь хлебцы, добавь яйцо и томаты."]),
        Recipe(title: "Кефирный смузи с ягодами", subtitle: "Лёгкий перекус после тренировки", category: .snack, calories: 194, protein: 12, fat: 5, carbs: 27, duration: 4, symbol: "cup.and.saucer.fill", ingredients: ["Кефир 1% — 250 мл", "Ягоды — 120 г", "Банан — ½ шт.", "Семена льна — 1 ч. л."], steps: ["Положи ягоды и банан в блендер.", "Добавь кефир и семена льна.", "Взбей до однородности."]),
        Recipe(title: "Эдамаме с чили и лимоном", subtitle: "Растительный белок в стручках", category: .snack, calories: 186, protein: 17, fat: 8, carbs: 14, duration: 8, symbol: "leaf.fill", ingredients: ["Эдамаме замороженные — 160 г", "Лимонный сок — 1 ч. л.", "Хлопья чили — щепотка", "Соль — щепотка"], steps: ["Отвари эдамаме 4–5 минут.", "Слей воду и сбрызни лимонным соком.", "Добавь чили и немного соли."]),
        Recipe(title: "Капрезе с моцареллой", subtitle: "Свежий перекус без готовки", category: .snack, calories: 227, protein: 15, fat: 14, carbs: 11, duration: 5, symbol: "heart.fill", ingredients: ["Моцарелла мини — 100 г", "Томаты черри — 150 г", "Базилик — горсть", "Бальзамический уксус — 1 ч. л.", "Перец"], steps: ["Разрежь томаты и моцареллу пополам.", "Смешай с листьями базилика.", "Добавь уксус и свежемолотый перец."]),

        Recipe(title: "Овсяный брауни с какао", subtitle: "Шоколадный десерт из духовки", category: .dessert, calories: 211, protein: 8, fat: 8, carbs: 29, duration: 30, symbol: "square.fill", ingredients: ["Банан — 1 шт.", "Овсяная мука — 50 г", "Какао — 15 г", "Яйцо — 1 шт.", "Тёмный шоколад — 15 г", "Разрыхлитель — ½ ч. л."], steps: ["Разомни банан и смешай с яйцом, мукой, какао и разрыхлителем.", "Добавь рубленый шоколад.", "Выпекай в небольшой форме 18–20 минут при 180°C."]),
        Recipe(title: "Творожный чизкейк в стакане", subtitle: "Порционный десерт с высоким белком", category: .dessert, calories: 244, protein: 23, fat: 8, carbs: 23, duration: 10, symbol: "birthday.cake.fill", ingredients: ["Творог 5% — 170 г", "Греческий йогурт — 50 г", "Ягоды — 80 г", "Овсяное печенье — 15 г", "Мёд — 1 ч. л."], steps: ["Взбей творог с йогуртом и мёдом до кремовой текстуры.", "Раскроши печенье на дно стакана.", "Выложи крем и ягоды слоями."]),
        Recipe(title: "Малиновое мороженое из йогурта", subtitle: "Десерт из трёх ингредиентов", category: .dessert, calories: 174, protein: 14, fat: 4, carbs: 23, duration: 5, symbol: "snowflake", ingredients: ["Замороженная малина — 150 г", "Греческий йогурт — 150 г", "Мёд — 1 ч. л."], steps: ["Дай малине постоять 3–4 минуты.", "Взбей ягоды с йогуртом и мёдом в блендере.", "Ешь сразу как мягкое мороженое или заморозь на час."]),
        Recipe(title: "Апельсиновый чиа-крем", subtitle: "Цитрусовый десерт с клетчаткой", category: .dessert, calories: 208, protein: 9, fat: 9, carbs: 27, duration: 10, symbol: "drop.fill", ingredients: ["Семена чиа — 20 г", "Молоко — 160 мл", "Апельсин — 1 шт.", "Греческий йогурт — 70 г", "Ваниль"], steps: ["Смешай чиа, молоко и ваниль.", "Оставь в холодильнике на 2 часа.", "Добавь йогурт, цедру и кусочки апельсина перед подачей."]),

        // Простые овощные рецепты
        Recipe(title: "Оладьи из кабачка", subtitle: "Хрустящие и лёгкие, всего 20 минут", category: .lunch, calories: 276, protein: 18, fat: 13, carbs: 24, duration: 20, symbol: "leaf.fill", ingredients: ["Кабачок — 250 г", "Яйцо — 1 шт.", "Овсяная мука — 35 г", "Сыр — 25 г", "Йогурт для подачи — 40 г"], steps: ["Натри кабачок, посоли и хорошо отожми сок.", "Смешай с яйцом, мукой и сыром.", "Обжарь небольшие оладьи на антипригарной сковороде, подавай с йогуртом."]),
        Recipe(title: "Баклажан с томатами и моцареллой", subtitle: "Мини-пицца из овощей", category: .lunch, calories: 324, protein: 18, fat: 21, carbs: 19, duration: 30, symbol: "circle.grid.cross.fill", ingredients: ["Баклажан — 1 крупный", "Томатный соус — 100 г", "Моцарелла — 80 г", "Томаты черри — 80 г", "Базилик"], steps: ["Нарежь баклажан кружками и запекай 12 минут при 200°C.", "Смажь соусом, добавь моцареллу и томаты.", "Верни в духовку ещё на 8–10 минут, укрась базиликом."]),
        Recipe(title: "Быстрый рататуй", subtitle: "Кабачок, баклажан и перец на сковороде", category: .lunch, calories: 219, protein: 7, fat: 11, carbs: 26, duration: 25, symbol: "carrot.fill", ingredients: ["Кабачок — 180 г", "Баклажан — 180 г", "Болгарский перец — 120 г", "Томаты — 200 г", "Оливковое масло — 1 ч. л.", "Чеснок и травы"], steps: ["Нарежь все овощи крупными кубиками.", "Обжарь баклажан и перец 5 минут, добавь кабачок.", "Добавь томаты, чеснок и травы, туши под крышкой 12 минут."]),
        Recipe(title: "Паста из кабачка с курицей", subtitle: "Лёгкий обед без тяжёлого гарнира", category: .lunch, calories: 337, protein: 39, fat: 15, carbs: 16, duration: 20, symbol: "fork.knife.circle.fill", ingredients: ["Куриное филе — 150 г", "Кабачок — 300 г", "Томаты черри — 120 г", "Пармезан — 15 г", "Оливковое масло — 1 ч. л."], steps: ["Нарежь кабачок тонкими лентами овощечисткой.", "Обжарь курицу, добавь томаты.", "Вмешай кабачковые ленты на 2 минуты и посыпь пармезаном."]),
        Recipe(title: "Нут с баклажаном в томатах", subtitle: "Сытный обед из одной сковороды", category: .lunch, calories: 398, protein: 15, fat: 12, carbs: 59, duration: 25, symbol: "leaf.circle.fill", ingredients: ["Нут, готовый — 160 г", "Баклажан — 220 г", "Томаты в собственном соку — 200 г", "Лук — ½ шт.", "Оливковое масло — 1 ч. л.", "Паприка"], steps: ["Обжарь кубики баклажана и лук до румяности.", "Добавь нут, томаты и паприку.", "Туши 12 минут под крышкой, подавай с зеленью."]),
        Recipe(title: "Тёплый салат с грибами и перцем", subtitle: "Простой обед с гречкой", category: .lunch, calories: 366, protein: 15, fat: 12, carbs: 51, duration: 20, symbol: "leaf.fill", ingredients: ["Гречка, готовая — 160 г", "Шампиньоны — 180 г", "Болгарский перец — 120 г", "Руккола — 40 г", "Фета — 35 г", "Оливковое масло — 1 ч. л."], steps: ["Обжарь грибы и перец до мягкости.", "Прогрей гречку и смешай с овощами.", "Выложи на рукколу, добавь фету и масло."]),
        Recipe(title: "Рулетики из кабачка с творогом", subtitle: "Овощная закуска или лёгкий обед", category: .lunch, calories: 258, protein: 24, fat: 14, carbs: 12, duration: 20, symbol: "leaf.fill", ingredients: ["Кабачок — 250 г", "Творог 5% — 170 г", "Чеснок — 1 зубчик", "Укроп", "Томаты черри — 100 г"], steps: ["Нарежь кабачок длинными тонкими лентами и обжарь по минуте.", "Смешай творог с чесноком и укропом.", "Нанеси начинку на ленты, сверни рулетики и подавай с томатами."]),

        Recipe(title: "Лодочки из баклажана с индейкой", subtitle: "Запекается без сложной подготовки", category: .dinner, calories: 378, protein: 34, fat: 18, carbs: 23, duration: 40, symbol: "leaf.circle.fill", ingredients: ["Баклажан — 1 крупный", "Фарш индейки — 160 г", "Томатное пюре — 120 г", "Лук — ½ шт.", "Сыр — 30 г"], steps: ["Разрежь баклажан вдоль, надрежь мякоть и запекай 15 минут при 190°C.", "Обжарь фарш с луком, мякотью баклажана и томатным пюре.", "Наполни лодочки, добавь сыр и запекай ещё 12 минут."]),
        Recipe(title: "Омлет с кабачком и шпинатом", subtitle: "Ужин за 15 минут", category: .dinner, calories: 294, protein: 24, fat: 19, carbs: 10, duration: 15, symbol: "sun.max.fill", ingredients: ["Яйца — 2 шт.", "Белки — 2 шт.", "Кабачок — 150 г", "Шпинат — горсть", "Сыр — 25 г"], steps: ["Тонко нарежь кабачок и обжарь 3 минуты.", "Добавь шпинат и взбитые яйца с белками.", "Посыпь сыром и готовь под крышкой до схватывания."]),
        Recipe(title: "Овощная сковорода с яйцом", subtitle: "Томаты, перец и брокколи", category: .dinner, calories: 302, protein: 21, fat: 17, carbs: 20, duration: 20, symbol: "flame.fill", ingredients: ["Яйца — 2 шт.", "Брокколи — 150 г", "Болгарский перец — 100 г", "Томаты — 150 г", "Фета — 30 г", "Оливковое масло — 1 ч. л."], steps: ["Обжарь брокколи и перец 5 минут.", "Добавь томаты и сделай два углубления.", "Разбей яйца, накрой крышкой, затем добавь раскрошенную фету."]),
        Recipe(title: "Запечённый кабачок с рикоттой", subtitle: "Нежный овощной ужин", category: .dinner, calories: 317, protein: 20, fat: 20, carbs: 17, duration: 30, symbol: "leaf.fill", ingredients: ["Кабачки — 2 шт.", "Рикотта — 120 г", "Томаты черри — 120 г", "Пармезан — 15 г", "Базилик"], steps: ["Разрежь кабачки вдоль и вынь немного мякоти.", "Смешай рикотту с нарезанными томатами и базиликом.", "Наполни кабачки, посыпь пармезаном и запекай 20 минут при 190°C."]),
        Recipe(title: "Индейка с баклажаном в воке", subtitle: "Простой белковый ужин", category: .dinner, calories: 395, protein: 38, fat: 16, carbs: 27, duration: 25, symbol: "flame.circle.fill", ingredients: ["Филе индейки — 160 г", "Баклажан — 200 г", "Болгарский перец — 100 г", "Соевый соус — 1 ст. л.", "Кунжут — 1 ч. л.", "Рис, готовый — 80 г"], steps: ["Обжарь индейку тонкими полосками до готовности.", "Добавь баклажан и перец, готовь до мягкости.", "Влей соевый соус, посыпь кунжутом и подавай с рисом."]),
        Recipe(title: "Чечевица с баклажаном и шпинатом", subtitle: "Тушёный овощной ужин", category: .dinner, calories: 356, protein: 21, fat: 9, carbs: 52, duration: 30, symbol: "carrot.fill", ingredients: ["Красная чечевица — 75 г", "Баклажан — 180 г", "Шпинат — 80 г", "Томаты в собственном соку — 200 г", "Лук — ½ шт.", "Карри"], steps: ["Обжарь лук и баклажан 5 минут.", "Добавь чечевицу, томаты, воду и карри.", "Вари 18 минут, в конце вмешай шпинат."]),
        Recipe(title: "Курица с овощами на противне", subtitle: "Ужин без стояния у плиты", category: .dinner, calories: 374, protein: 42, fat: 13, carbs: 23, duration: 35, symbol: "oven.fill", ingredients: ["Куриное филе — 170 г", "Кабачок — 180 г", "Баклажан — 150 г", "Болгарский перец — 120 г", "Оливковое масло — 1 ч. л.", "Сухие травы"], steps: ["Нарежь курицу и овощи крупными кусочками.", "Смешай с маслом, травами и щепоткой соли.", "Запекай на противне 25 минут при 200°C."])
    ]
}

private enum NutritionSection: String, CaseIterable, Identifiable {
    case recipes = "Рецепты"
    case products = "Продукты"

    var id: String { rawValue }
    var icon: String { self == .recipes ? "book.closed.fill" : "basket.fill" }
}

private struct RecipesView: View {
    @State private var selectedCategory: RecipeCategory?
    @State private var selectedRecipe: Recipe?
    @State private var selectedProduct: FoodProduct?
    @State private var selectedSection: NutritionSection = .recipes
    @State private var searchText = ""
    @State private var selectedFoodCategory: FoodCategory?
    @State private var productSearchText = ""

    private var recipes: [Recipe] {
        RecipeLibrary.all.filter { recipe in
            (selectedCategory == nil || recipe.category == selectedCategory) && recipe.matches(searchText)
        }
    }

    private var products: [FoodProduct] {
        FoodLibrary.all.filter { product in
            (selectedFoodCategory == nil || product.category == selectedFoodCategory) && product.matches(productSearchText)
        }
    }

    private var popularRecipes: [Recipe] { Array(RecipeLibrary.all.prefix(3)) }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(colors: [Color(red: 0.04, green: 0.06, blue: 0.14), Color(red: 0.10, green: 0.08, blue: 0.24)], startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        nutritionTitle
                        VStack(alignment: .leading, spacing: 18) {
                            Text("Рецепты и продукты")
                                .font(.title2.bold())
                                .foregroundStyle(.white)
                            sectionPicker
                            if selectedSection == .recipes {
                                recipesContent
                            } else {
                                productsContent
                            }
                        }
                        .padding(16)
                        .background(.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 28))
                        .overlay(RoundedRectangle(cornerRadius: 28).stroke(.cyan.opacity(0.48), lineWidth: 1.2))
                    }
                    .padding(.horizontal, 20).padding(.bottom, 28)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $selectedRecipe) { recipe in RecipeDetailView(recipe: recipe) }
            .sheet(item: $selectedProduct) { product in ProductDetailView(product: product) }
        }
    }

    private var nutritionTitle: some View {
        HStack(spacing: 10) {
            Text("Питайся").foregroundStyle(.white)
            Text("правильно")
                .foregroundStyle(LinearGradient(colors: [.mint, .cyan], startPoint: .leading, endPoint: .trailing))
        }
        .font(.system(size: 34, weight: .bold, design: .rounded))
        .minimumScaleFactor(0.72)
        .padding(.top, 14)
    }

    private var sectionPicker: some View {
        HStack(spacing: 4) {
            ForEach(NutritionSection.allCases) { section in
                Button { selectedSection = section } label: {
                    Label(section.rawValue, systemImage: section.icon)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(selectedSection == section ? .cyan : .white.opacity(0.52))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(selectedSection == section ? .cyan.opacity(0.17) : .clear, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(.white.opacity(0.07), in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.08)))
    }

    private var recipesContent: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack {
                Text("Популярные рецепты").font(.headline).foregroundStyle(.white)
                Spacer()
                Text("Смотреть все").font(.subheadline.weight(.semibold)).foregroundStyle(.cyan)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(popularRecipes) { recipe in
                        Button { selectedRecipe = recipe } label: { NutritionRecipeCard(recipe: recipe) }
                            .buttonStyle(.plain)
                    }
                }
            }
            searchField
            categoryPicker
            HStack(alignment: .firstTextBaseline) {
                Text(selectedCategory?.rawValue ?? "Все рецепты").font(.title3.bold()).foregroundStyle(.white)
                Spacer()
                Text("\(recipes.count)").font(.subheadline.weight(.bold)).foregroundStyle(.mint)
            }
            if recipes.isEmpty {
                ContentUnavailableView("Ничего не найдено", systemImage: "magnifyingglass", description: Text("Попробуй изменить запрос или выбрать другую категорию."))
                    .foregroundStyle(.white.opacity(0.75)).frame(maxWidth: .infinity).padding(.vertical, 24)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(recipes) { recipe in
                        Button { selectedRecipe = recipe } label: { RecipeCard(recipe: recipe) }
                            .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var productsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Каталог продуктов").font(.headline).foregroundStyle(.white)
            productCategoryPicker
            productSearchField
            HStack {
                Text("Продукт").frame(maxWidth: .infinity, alignment: .leading)
                Text("ккал").frame(width: 42)
                Text("Б").frame(width: 34)
                Text("Ж").frame(width: 34)
                Text("У").frame(width: 34)
            }
            .font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.5))
            ForEach(products) { product in
                Button { selectedProduct = product } label: { NutritionProductRow(product: product) }
                    .buttonStyle(.plain)
            }
            Text("Значения приведены на 100 г продукта.")
                .font(.caption).foregroundStyle(.white.opacity(0.5))
        }
    }

    private var categoryPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 9) {
                RecipeCategoryChip(title: "Все", icon: "square.grid.2x2.fill", tint: .white, isSelected: selectedCategory == nil) { selectedCategory = nil }
                ForEach(RecipeCategory.allCases) { category in
                    RecipeCategoryChip(title: category.rawValue, icon: category.icon, tint: category.tint, isSelected: selectedCategory == category) { selectedCategory = category }
                }
            }
        }
    }

    private var productCategoryPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FoodCategoryChip(title: "Все", systemIcon: "square.grid.2x2.fill", tint: .mint, isSelected: selectedFoodCategory == nil) { selectedFoodCategory = nil }
                ForEach(FoodCategory.allCases) { category in
                    FoodCategoryChip(title: category.shortTitle, systemIcon: category.icon, tint: .mint, isSelected: selectedFoodCategory == category) { selectedFoodCategory = category }
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.white.opacity(0.58))
            TextField("Название, ингредиент или БЖУ", text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundStyle(.white)
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.white.opacity(0.55))
                }
                .accessibilityLabel("Очистить поиск")
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.10)))
    }

    private var productSearchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.white.opacity(0.58))
            TextField("Поиск продуктов", text: $productSearchText)
                .textInputAutocapitalization(.never).autocorrectionDisabled().foregroundStyle(.white)
            if !productSearchText.isEmpty {
                Button { productSearchText = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.white.opacity(0.55)) }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.13)))
    }
}

private struct RecipeCategoryChip: View {
    let title: String
    let icon: String
    let tint: Color
    let isSelected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon).font(.subheadline.weight(.semibold)).foregroundStyle(isSelected ? .black : .white.opacity(0.78))
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(isSelected ? tint : .white.opacity(0.10), in: Capsule())
        }.buttonStyle(.plain)
    }
}

private struct RecipeCard: View {
    let recipe: Recipe
    var body: some View {
        HStack(spacing: 14) {
            Image(recipe.category.imageName)
                .resizable()
                .scaledToFill()
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 17))
            VStack(alignment: .leading, spacing: 5) {
                Text(recipe.title).font(.headline).foregroundStyle(.white)
                Text(recipe.subtitle).font(.caption).foregroundStyle(.white.opacity(0.58)).lineLimit(1)
                HStack(spacing: 9) {
                    Label("\(recipe.calories) ккал", systemImage: "flame.fill")
                    Label("\(recipe.duration) мин", systemImage: "clock.fill")
                }.font(.caption2.weight(.semibold)).foregroundStyle(.white.opacity(0.72))
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.white.opacity(0.42))
        }
        .padding(15).background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 21))
        .overlay(RoundedRectangle(cornerRadius: 21).stroke(.white.opacity(0.08)))
    }
}

private struct NutritionRecipeCard: View {
    let recipe: Recipe

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                Image(recipe.category.imageName)
                    .resizable().scaledToFill()
                    .frame(width: 174, height: 118)
                    .clipped()
                Text("\(recipe.duration) мин")
                    .font(.caption2.weight(.bold)).foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(.black.opacity(0.6), in: Capsule())
                    .padding(8)
            }
            Text(recipe.title).font(.subheadline.weight(.semibold)).foregroundStyle(.white).lineLimit(2)
            HStack(spacing: 9) {
                NutritionMiniMacro(value: "\(recipe.calories)", title: "ккал", tint: .mint)
                NutritionMiniMacro(value: "\(recipe.protein)", title: "Б", tint: .white)
                NutritionMiniMacro(value: "\(recipe.fat)", title: "Ж", tint: .white)
                NutritionMiniMacro(value: "\(recipe.carbs)", title: "У", tint: .white)
            }
        }
        .frame(width: 174, alignment: .leading)
        .padding(8)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.12)))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

private struct NutritionMiniMacro: View {
    let value: String
    let title: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.caption.weight(.bold)).foregroundStyle(tint)
            Text(title).font(.caption2).foregroundStyle(.white.opacity(0.55))
        }
    }
}

private struct FoodEmoji: View {
    let value: String
    let size: CGFloat

    var body: some View {
        Text(value)
            .font(.custom("AppleColorEmoji", size: size))
            .fixedSize()
            .accessibilityHidden(true)
    }
}

private struct FoodProductIcon: View {
    let product: FoodProduct
    let size: CGFloat

    var body: some View {
        Image(systemName: product.systemIcon)
            .font(.system(size: size, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(product.category.tint)
            .accessibilityHidden(true)
    }
}

private struct NutritionProductRow: View {
    let product: FoodProduct

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 9) {
                FoodProductIcon(product: product, size: 21)
                    .frame(width: 38, height: 38)
                    .background(product.category.tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 1) {
                    Text(product.title).font(.subheadline.weight(.semibold)).foregroundStyle(.white).lineLimit(1)
                    Text("100 г").font(.caption2).foregroundStyle(.white.opacity(0.5))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(product.calories)").foregroundStyle(.mint).frame(width: 42)
            Text(product.proteinText).frame(width: 34)
            Text(product.fatText).frame(width: 34)
            Text(product.carbsText).frame(width: 34)
            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.white.opacity(0.55))
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.white.opacity(0.9))
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.1)))
    }
}

private struct RecipeDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let recipe: Recipe
    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(colors: [Color(red: 0.04, green: 0.06, blue: 0.14), Color(red: 0.10, green: 0.08, blue: 0.24)], startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 22) {
                        VStack(alignment: .leading, spacing: 10) {
                            Image(recipe.category.imageName)
                                .resizable()
                                .scaledToFill()
                                .frame(maxWidth: .infinity)
                                .frame(height: 190)
                                .clipShape(RoundedRectangle(cornerRadius: 24))
                            Text(recipe.title).font(.largeTitle.bold()).foregroundStyle(.white)
                            Text(recipe.subtitle).foregroundStyle(.white.opacity(0.65))
                            Label("\(recipe.duration) минут", systemImage: "clock.fill").font(.subheadline.weight(.semibold)).foregroundStyle(recipe.category.tint)
                        }
                        HStack(spacing: 9) {
                            RecipeNutrition(value: "\(recipe.calories)", title: "ккал", tint: .orange)
                            RecipeNutrition(value: "\(recipe.protein) г", title: "белки", tint: .cyan)
                            RecipeNutrition(value: "\(recipe.fat) г", title: "жиры", tint: .pink)
                            RecipeNutrition(value: "\(recipe.carbs) г", title: "углеводы", tint: .purple)
                        }
                        RecipeSection(title: "Ингредиенты", symbol: "basket.fill") {
                            ForEach(recipe.ingredients, id: \.self) { ingredient in
                                Label(ingredient, systemImage: "checkmark.circle.fill").font(.subheadline).foregroundStyle(.white.opacity(0.84))
                            }
                        }
                        RecipeSection(title: "Как приготовить", symbol: "list.number") {
                            ForEach(Array(recipe.steps.enumerated()), id: \.offset) { index, step in
                                HStack(alignment: .top, spacing: 11) {
                                    Text("\(index + 1)").font(.caption.bold()).foregroundStyle(.black).frame(width: 23, height: 23).background(recipe.category.tint, in: Circle())
                                    Text(step).font(.subheadline).foregroundStyle(.white.opacity(0.85)).fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                    .padding(20).padding(.bottom, 28)
                }
            }
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Готово") { dismiss() }.foregroundStyle(.white) } }
        }
    }
}

private struct RecipeNutrition: View {
    let value: String
    let title: String
    let tint: Color
    var body: some View {
        VStack(spacing: 3) {
            Text(value).font(.subheadline.bold()).foregroundStyle(tint)
            Text(title).font(.caption2).foregroundStyle(.white.opacity(0.58))
        }.frame(maxWidth: .infinity).padding(.vertical, 10).background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct RecipeSection<Content: View>: View {
    let title: String
    let symbol: String
    let content: Content

    init(title: String, symbol: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.symbol = symbol
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Label(title, systemImage: symbol).font(.headline).foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 11) { content }
        }
        .padding(18).background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 22))
    }
}

private enum FoodCategory: String, CaseIterable, Identifiable {
    case fruits = "Фрукты и ягоды"
    case vegetables = "Овощи и грибы"
    case grains = "Крупы и хлеб"
    case legumes = "Бобовые"
    case protein = "Мясо, рыба, яйца"
    case dairy = "Молочное"
    case nuts = "Орехи и семена"
    case sweets = "Сладости"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .fruits: "apple.logo"
        case .vegetables: "carrot.fill"
        case .grains: "bowl.fill"
        case .legumes: "leaf.fill"
        case .protein: "fish.fill"
        case .dairy: "cup.and.saucer.fill"
        case .nuts: "tree.fill"
        case .sweets: "birthday.cake.fill"
        }
    }
    var tint: Color {
        switch self {
        case .fruits: .pink
        case .vegetables: .green
        case .grains: .orange
        case .legumes: .mint
        case .protein: .cyan
        case .dairy: .blue
        case .nuts: .brown
        case .sweets: .purple
        }
    }
    var emoji: String {
        switch self {
        case .fruits: "🍎"
        case .vegetables: "🥬"
        case .grains: "🌾"
        case .legumes: "🌱"
        case .protein: "🐟"
        case .dairy: "🥛"
        case .nuts: "🥜"
        case .sweets: "🍫"
        }
    }
    var shortTitle: String {
        switch self {
        case .fruits: "Фрукты"
        case .vegetables: "Овощи"
        case .grains: "Крупы"
        case .legumes: "Бобовые"
        case .protein: "Белки"
        case .dairy: "Молочные"
        case .nuts: "Орехи"
        case .sweets: "Сладости"
        }
    }
}

private struct FoodProduct: Identifiable {
    let title: String
    let category: FoodCategory
    let calories: Int
    let protein: Double
    let fat: Double
    let carbs: Double

    var id: String { "\(category.rawValue)-\(title)" }
    var proteinText: String { grams(protein) }
    var fatText: String { grams(fat) }
    var carbsText: String { grams(carbs) }
    var emoji: String {
        switch title {
        case "Яблоко": "🍎"
        case "Банан": "🍌"
        case "Апельсин": "🍊"
        case "Груша": "🍐"
        case "Виноград": "🍇"
        case "Клубника": "🍓"
        case "Черника": "🍇"
        case "Малина": "🍓"
        case "Киви": "🥝"
        case "Манго": "🥭"
        case "Персик": "🍑"
        case "Грейпфрут": "🍊"
        case "Кабачок", "Огурец": "🥒"
        case "Баклажан": "🍆"
        case "Томат": "🍅"
        case "Болгарский перец": "🍅"
        case "Брокколи", "Цветная капуста": "🥦"
        case "Морковь": "🥕"
        case "Свёкла": "🥕"
        case "Шпинат": "🥬"
        case "Картофель": "🥔"
        case "Батат": "🍠"
        case "Шампиньоны": "🍄"
        case "Лук": "🧅"
        case "Овсяные хлопья": "🥣"
        case "Рис белый", "Рис бурый": "🍚"
        case "Цельнозерновая паста": "🍝"
        case "Цельнозерновой хлеб": "🍞"
        case "Цельнозерновая тортилья": "🌯"
        case "Гречка", "Киноа", "Булгур", "Кускус": "🌾"
        case "Чечевица сухая", "Нут сухой", "Фасоль сухая", "Горох сухой", "Эдамаме", "Зелёный горошек": "🌱"
        case "Тофу": "🍱"
        case "Хумус": "🥣"
        case "Куриная грудка": "🍗"
        case "Филе индейки": "🍗"
        case "Говядина постная": "🥩"
        case "Лосось", "Треска", "Тунец в собственном соку": "🐟"
        case "Креветки": "🦐"
        case "Яйцо куриное": "🥚"
        case "Молоко 2,5%", "Кефир 1%": "🥛"
        case "Йогурт греческий 2%", "Йогурт натуральный 3%": "🥣"
        case "Творог 5%", "Моцарелла", "Рикотта", "Пармезан": "🧀"
        case "Миндаль", "Грецкий орех", "Кешью": "🌰"
        case "Арахис", "Арахисовая паста": "🥜"
        case "Тыквенные семечки", "Семена подсолнечника", "Семена чиа": "🌻"
        case "Тёмный шоколад 70%", "Молочный шоколад", "Белый шоколад": "🍫"
        case "Мёд": "🍯"
        case "Сахар": "🧂"
        case "Мармелад": "🍬"
        case "Мороженое сливочное": "🍨"
        case "Овсяное печенье": "🍪"
        case "Протеиновый батончик": "🍫"
        default: category.emoji
        }
    }
    var systemIcon: String {
        switch title {
        case "Куриная грудка", "Филе индейки": "drumstick.fill"
        case "Говядина постная": "fork.knife"
        case "Лосось", "Треска", "Тунец в собственном соку", "Креветки": "fish.fill"
        case "Яйцо куриное": "oval.fill"
        case "Молоко 2,5%", "Кефир 1%": "waterbottle.fill"
        case "Йогурт греческий 2%", "Йогурт натуральный 3%", "Творог 5%": "cup.and.saucer.fill"
        case "Моцарелла", "Рикотта", "Пармезан": "circle.grid.cross.fill"
        case "Тёмный шоколад 70%", "Молочный шоколад", "Белый шоколад": "birthday.cake.fill"
        case "Мёд": "drop.fill"
        case "Овсяное печенье", "Протеиновый батончик": "takeoutbag.and.cup.and.straw.fill"
        default:
            switch category {
            case .fruits: "leaf.circle.fill"
            case .vegetables: "carrot.fill"
            case .grains: "bowl.fill"
            case .legumes: "leaf.fill"
            case .protein: "fish.fill"
            case .dairy: "cup.and.saucer.fill"
            case .nuts: "tree.fill"
            case .sweets: "birthday.cake.fill"
            }
        }
    }

    func matches(_ query: String) -> Bool {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let index = "\(title) \(category.rawValue) \(calories) \(proteinText) белки \(fatText) жиры \(carbsText) углеводы"
        return normalizedQuery.isEmpty || index.localizedStandardContains(normalizedQuery)
    }

    private func grams(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }
}

private enum FoodLibrary {
    static let all: [FoodProduct] = [
        // Фрукты и ягоды
        FoodProduct(title: "Яблоко", category: .fruits, calories: 52, protein: 0.3, fat: 0.2, carbs: 13.8),
        FoodProduct(title: "Банан", category: .fruits, calories: 89, protein: 1.1, fat: 0.3, carbs: 22.8),
        FoodProduct(title: "Апельсин", category: .fruits, calories: 47, protein: 0.9, fat: 0.1, carbs: 11.8),
        FoodProduct(title: "Груша", category: .fruits, calories: 57, protein: 0.4, fat: 0.1, carbs: 15.2),
        FoodProduct(title: "Виноград", category: .fruits, calories: 69, protein: 0.7, fat: 0.2, carbs: 18.1),
        FoodProduct(title: "Клубника", category: .fruits, calories: 32, protein: 0.7, fat: 0.3, carbs: 7.7),
        FoodProduct(title: "Черника", category: .fruits, calories: 57, protein: 0.7, fat: 0.3, carbs: 14.5),
        FoodProduct(title: "Малина", category: .fruits, calories: 52, protein: 1.2, fat: 0.7, carbs: 12),
        FoodProduct(title: "Киви", category: .fruits, calories: 61, protein: 1.1, fat: 0.5, carbs: 14.7),
        FoodProduct(title: "Манго", category: .fruits, calories: 60, protein: 0.8, fat: 0.4, carbs: 15),
        FoodProduct(title: "Персик", category: .fruits, calories: 39, protein: 0.9, fat: 0.3, carbs: 9.5),
        FoodProduct(title: "Грейпфрут", category: .fruits, calories: 42, protein: 0.8, fat: 0.1, carbs: 10.7),

        // Овощи и грибы
        FoodProduct(title: "Кабачок", category: .vegetables, calories: 17, protein: 1.2, fat: 0.3, carbs: 3.1),
        FoodProduct(title: "Баклажан", category: .vegetables, calories: 25, protein: 1, fat: 0.2, carbs: 5.9),
        FoodProduct(title: "Огурец", category: .vegetables, calories: 15, protein: 0.7, fat: 0.1, carbs: 3.6),
        FoodProduct(title: "Томат", category: .vegetables, calories: 18, protein: 0.9, fat: 0.2, carbs: 3.9),
        FoodProduct(title: "Болгарский перец", category: .vegetables, calories: 31, protein: 1, fat: 0.3, carbs: 6),
        FoodProduct(title: "Брокколи", category: .vegetables, calories: 34, protein: 2.8, fat: 0.4, carbs: 6.6),
        FoodProduct(title: "Цветная капуста", category: .vegetables, calories: 25, protein: 1.9, fat: 0.3, carbs: 5),
        FoodProduct(title: "Морковь", category: .vegetables, calories: 41, protein: 0.9, fat: 0.2, carbs: 9.6),
        FoodProduct(title: "Свёкла", category: .vegetables, calories: 43, protein: 1.6, fat: 0.2, carbs: 10),
        FoodProduct(title: "Шпинат", category: .vegetables, calories: 23, protein: 2.9, fat: 0.4, carbs: 3.6),
        FoodProduct(title: "Картофель", category: .vegetables, calories: 77, protein: 2, fat: 0.1, carbs: 17),
        FoodProduct(title: "Батат", category: .vegetables, calories: 86, protein: 1.6, fat: 0.1, carbs: 20.1),
        FoodProduct(title: "Шампиньоны", category: .vegetables, calories: 22, protein: 3.1, fat: 0.3, carbs: 3.3),
        FoodProduct(title: "Лук", category: .vegetables, calories: 40, protein: 1.1, fat: 0.1, carbs: 9.3),

        // Крупы и хлеб: сухой продукт, если не указано иначе
        FoodProduct(title: "Овсяные хлопья", category: .grains, calories: 379, protein: 13.2, fat: 6.5, carbs: 67.7),
        FoodProduct(title: "Гречка", category: .grains, calories: 343, protein: 13.3, fat: 3.4, carbs: 71.5),
        FoodProduct(title: "Рис белый", category: .grains, calories: 365, protein: 7.1, fat: 0.7, carbs: 80),
        FoodProduct(title: "Рис бурый", category: .grains, calories: 370, protein: 7.9, fat: 2.9, carbs: 77.2),
        FoodProduct(title: "Киноа", category: .grains, calories: 368, protein: 14.1, fat: 6.1, carbs: 64.2),
        FoodProduct(title: "Булгур", category: .grains, calories: 342, protein: 12.3, fat: 1.3, carbs: 75.9),
        FoodProduct(title: "Кускус", category: .grains, calories: 376, protein: 12.8, fat: 0.6, carbs: 77.4),
        FoodProduct(title: "Цельнозерновая паста", category: .grains, calories: 348, protein: 13, fat: 2.5, carbs: 68),
        FoodProduct(title: "Цельнозерновой хлеб", category: .grains, calories: 247, protein: 13, fat: 4.2, carbs: 41),
        FoodProduct(title: "Цельнозерновая тортилья", category: .grains, calories: 312, protein: 8, fat: 8, carbs: 48),

        // Бобовые
        FoodProduct(title: "Чечевица сухая", category: .legumes, calories: 352, protein: 24.6, fat: 1.1, carbs: 63.4),
        FoodProduct(title: "Нут сухой", category: .legumes, calories: 364, protein: 19.3, fat: 6, carbs: 60.7),
        FoodProduct(title: "Фасоль сухая", category: .legumes, calories: 333, protein: 21, fat: 1.2, carbs: 60),
        FoodProduct(title: "Горох сухой", category: .legumes, calories: 341, protein: 24, fat: 1, carbs: 60),
        FoodProduct(title: "Тофу", category: .legumes, calories: 144, protein: 17.3, fat: 8.7, carbs: 2.8),
        FoodProduct(title: "Эдамаме", category: .legumes, calories: 122, protein: 11.9, fat: 5.2, carbs: 8.9),
        FoodProduct(title: "Зелёный горошек", category: .legumes, calories: 81, protein: 5.4, fat: 0.4, carbs: 14.5),
        FoodProduct(title: "Хумус", category: .legumes, calories: 166, protein: 7.9, fat: 9.6, carbs: 14.3),

        // Мясо, рыба, яйца
        FoodProduct(title: "Куриная грудка", category: .protein, calories: 120, protein: 22.5, fat: 2.6, carbs: 0),
        FoodProduct(title: "Филе индейки", category: .protein, calories: 114, protein: 23.7, fat: 1.2, carbs: 0),
        FoodProduct(title: "Говядина постная", category: .protein, calories: 137, protein: 21, fat: 5, carbs: 0),
        FoodProduct(title: "Лосось", category: .protein, calories: 208, protein: 20, fat: 13, carbs: 0),
        FoodProduct(title: "Треска", category: .protein, calories: 82, protein: 18, fat: 0.7, carbs: 0),
        FoodProduct(title: "Тунец в собственном соку", category: .protein, calories: 116, protein: 25.5, fat: 0.8, carbs: 0),
        FoodProduct(title: "Креветки", category: .protein, calories: 99, protein: 24, fat: 0.3, carbs: 0.2),
        FoodProduct(title: "Яйцо куриное", category: .protein, calories: 143, protein: 12.6, fat: 9.5, carbs: 0.7),

        // Молочное
        FoodProduct(title: "Молоко 2,5%", category: .dairy, calories: 52, protein: 2.8, fat: 2.5, carbs: 4.7),
        FoodProduct(title: "Кефир 1%", category: .dairy, calories: 40, protein: 3, fat: 1, carbs: 4),
        FoodProduct(title: "Йогурт греческий 2%", category: .dairy, calories: 73, protein: 9.5, fat: 2, carbs: 3.5),
        FoodProduct(title: "Йогурт натуральный 3%", category: .dairy, calories: 61, protein: 3.5, fat: 3, carbs: 4.7),
        FoodProduct(title: "Творог 5%", category: .dairy, calories: 121, protein: 17, fat: 5, carbs: 3),
        FoodProduct(title: "Моцарелла", category: .dairy, calories: 254, protein: 18, fat: 19, carbs: 2),
        FoodProduct(title: "Рикотта", category: .dairy, calories: 174, protein: 11, fat: 13, carbs: 3),
        FoodProduct(title: "Пармезан", category: .dairy, calories: 431, protein: 38, fat: 29, carbs: 4),

        // Орехи и семена
        FoodProduct(title: "Миндаль", category: .nuts, calories: 579, protein: 21.2, fat: 49.9, carbs: 21.6),
        FoodProduct(title: "Грецкий орех", category: .nuts, calories: 654, protein: 15.2, fat: 65.2, carbs: 13.7),
        FoodProduct(title: "Арахис", category: .nuts, calories: 567, protein: 25.8, fat: 49.2, carbs: 16.1),
        FoodProduct(title: "Кешью", category: .nuts, calories: 553, protein: 18.2, fat: 43.8, carbs: 30.2),
        FoodProduct(title: "Тыквенные семечки", category: .nuts, calories: 559, protein: 30.2, fat: 49.1, carbs: 10.7),
        FoodProduct(title: "Семена подсолнечника", category: .nuts, calories: 584, protein: 20.8, fat: 51.5, carbs: 20),
        FoodProduct(title: "Семена чиа", category: .nuts, calories: 486, protein: 16.5, fat: 30.7, carbs: 42.1),
        FoodProduct(title: "Арахисовая паста", category: .nuts, calories: 588, protein: 25, fat: 50, carbs: 20),

        // Сладости: данные зависят от бренда, сверяй упаковку
        FoodProduct(title: "Тёмный шоколад 70%", category: .sweets, calories: 598, protein: 7.8, fat: 42.6, carbs: 45.9),
        FoodProduct(title: "Молочный шоколад", category: .sweets, calories: 535, protein: 7.6, fat: 29.7, carbs: 59.4),
        FoodProduct(title: "Белый шоколад", category: .sweets, calories: 539, protein: 5.9, fat: 32.1, carbs: 59.2),
        FoodProduct(title: "Мёд", category: .sweets, calories: 304, protein: 0.3, fat: 0, carbs: 82.4),
        FoodProduct(title: "Сахар", category: .sweets, calories: 387, protein: 0, fat: 0, carbs: 100),
        FoodProduct(title: "Мармелад", category: .sweets, calories: 320, protein: 0, fat: 0, carbs: 80),
        FoodProduct(title: "Мороженое сливочное", category: .sweets, calories: 207, protein: 3.5, fat: 11, carbs: 24),
        FoodProduct(title: "Овсяное печенье", category: .sweets, calories: 450, protein: 6, fat: 15, carbs: 70),
        FoodProduct(title: "Протеиновый батончик", category: .sweets, calories: 360, protein: 25, fat: 12, carbs: 35)
    ]
}

private struct ProductsView: View {
    @State private var selectedCategory: FoodCategory?
    @State private var selectedProduct: FoodProduct?
    @State private var searchText = ""

    private var products: [FoodProduct] {
        FoodLibrary.all.filter { product in
            (selectedCategory == nil || product.category == selectedCategory) && product.matches(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(colors: [Color(red: 0.04, green: 0.06, blue: 0.14), Color(red: 0.10, green: 0.08, blue: 0.24)], startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 19) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("СПРАВОЧНИК").font(.caption.weight(.bold)).tracking(2).foregroundStyle(.mint)
                            Text("Продукты и БЖУ").font(.largeTitle.bold()).foregroundStyle(.white)
                            Text("\(FoodLibrary.all.count) продуктов. Все значения указаны на 100 г.").font(.subheadline).foregroundStyle(.white.opacity(0.65))
                        }.padding(.top, 12)
                        productSearchField
                        categoryPicker
                        HStack {
                            Text("Продукт").frame(maxWidth: .infinity, alignment: .leading)
                            Text("ккал").frame(width: 42)
                            Text("Б").frame(width: 34)
                            Text("Ж").frame(width: 34)
                            Text("У").frame(width: 34)
                        }
                        .font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.5))
                        HStack(alignment: .firstTextBaseline) {
                            Text(selectedCategory?.rawValue ?? "Все продукты").font(.title3.bold()).foregroundStyle(.white)
                            Spacer()
                            Text("\(products.count)").font(.subheadline.weight(.bold)).foregroundStyle(.mint)
                        }
                        if products.isEmpty {
                            ContentUnavailableView("Ничего не найдено", systemImage: "magnifyingglass", description: Text("Попробуй другое название или категорию."))
                                .foregroundStyle(.white.opacity(0.75)).frame(maxWidth: .infinity).padding(.vertical, 34)
                        } else {
                            LazyVStack(spacing: 12) {
                                ForEach(products) { product in
                                    Button { selectedProduct = product } label: { ProductCard(product: product) }
                                        .buttonStyle(.plain)
                                }
                            }
                        }
                        Text("Калорийность и БЖУ ориентировочные: для готовых и брендовых продуктов сверяй этикетку.")
                            .font(.caption).foregroundStyle(.white.opacity(0.52)).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 20).padding(.bottom, 28)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $selectedProduct) { product in ProductDetailView(product: product) }
        }
    }

    private var categoryPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 9) {
                FoodCategoryChip(title: "Все", systemIcon: "square.grid.2x2.fill", tint: .white, isSelected: selectedCategory == nil) { selectedCategory = nil }
                ForEach(FoodCategory.allCases) { category in
                    FoodCategoryChip(title: category.rawValue, systemIcon: category.icon, tint: category.tint, isSelected: selectedCategory == category) { selectedCategory = category }
                }
            }
        }
    }

    private var productSearchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.white.opacity(0.58))
            TextField("Например: кабачок, йогурт, шоколад", text: $searchText)
                .textInputAutocapitalization(.never).autocorrectionDisabled().foregroundStyle(.white)
            if !searchText.isEmpty {
                Button { searchText = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.white.opacity(0.55)) }
                    .accessibilityLabel("Очистить поиск")
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.10)))
    }
}

private struct CommunityMessage: Identifiable, Equatable {
    let id: String
    let author: String
    let authorID: String
    let text: String
    let createdAt: Date
}

private enum CommunityReportReason: String, CaseIterable, Identifiable {
    case offensive = "Оскорбления или травля"
    case inappropriate = "Неприемлемый контент"
    case spam = "Спам или реклама"
    case personalData = "Личные данные"

    var id: String { rawValue }
}

private enum CommunityContentFilter {
    private static let blockedFragments = [
        "бляд", "блять", "хуй", "хуе", "хуё", "пизд", "еба", "ёба", "ебл", "гандон", "мраз", "долбо"
    ]

    static func rejectionReason(for text: String) -> String? {
        let normalized = text.lowercased().folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .current)
        if blockedFragments.contains(where: normalized.contains) {
            return "Сообщение содержит недопустимую лексику и не было отправлено."
        }
        return nil
    }
}

@MainActor
private final class CommunityChatStore: ObservableObject {
    private static let recordType = "CommunityMessage"
    private static let reportRecordType = "CommunityMessageReport"
    private static let blockedAuthorsKey = "blockedCommunityChatAuthors"
    private let database = CKContainer.default().publicCloudDatabase

    @Published private(set) var messages: [CommunityMessage] = []
    @Published private(set) var blockedAuthors: [String: String]
    @Published private(set) var isLoading = false
    @Published private(set) var isSending = false
    @Published var errorMessage: String?
    @Published var confirmationMessage: String?

    init() {
        guard let data = UserDefaults.standard.data(forKey: Self.blockedAuthorsKey),
              let authors = try? JSONDecoder().decode([String: String].self, from: data) else {
            blockedAuthors = [:]
            return
        }
        blockedAuthors = authors
    }

    func loadMessages(showProgress: Bool = true) async {
        if showProgress { isLoading = true }
        defer { if showProgress { isLoading = false } }

        let query = CKQuery(recordType: Self.recordType, predicate: NSPredicate(format: "isHidden == NO"))
        query.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]

        do {
            let result = try await database.records(matching: query, resultsLimit: 100)
            messages = result.matchResults.compactMap { _, result in
                guard case let .success(record) = result,
                      let text = record["text"] as? String,
                      !text.isEmpty else { return nil }
                return CommunityMessage(
                    id: record.recordID.recordName,
                    author: (record["author"] as? String) ?? "Спортсмен",
                    authorID: (record["authorID"] as? String) ?? record.recordID.recordName,
                    text: text,
                    createdAt: (record["createdAt"] as? Date) ?? record.creationDate ?? .now
                )
            }
            .filter { blockedAuthors[$0.authorID] == nil }
            .sorted { $0.createdAt < $1.createdAt }
        } catch {
            errorMessage = chatErrorMessage(for: error)
        }
    }

    func send(text: String, author: String, authorID: String) async -> Bool {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return false }
        if let rejectionReason = CommunityContentFilter.rejectionReason(for: trimmedText) {
            errorMessage = rejectionReason
            return false
        }

        isSending = true
        defer { isSending = false }

        let record = CKRecord(recordType: Self.recordType)
        record["text"] = String(trimmedText.prefix(1_000)) as NSString
        record["author"] = String(author.prefix(40)) as NSString
        record["authorID"] = authorID as NSString
        record["createdAt"] = Date() as NSDate
        record["isHidden"] = NSNumber(value: false)

        do {
            try await database.save(record)
            await loadMessages(showProgress: false)
            return true
        } catch {
            errorMessage = chatErrorMessage(for: error)
            return false
        }
    }

    func report(message: CommunityMessage, reason: CommunityReportReason, reporterID: String) async {
        let record = CKRecord(recordType: Self.reportRecordType)
        record["messageID"] = message.id as NSString
        record["reportedAuthorID"] = message.authorID as NSString
        record["reporterID"] = reporterID as NSString
        record["reason"] = reason.rawValue as NSString
        record["messageText"] = message.text as NSString
        record["reportedAt"] = Date() as NSDate

        do {
            try await database.save(record)
            confirmationMessage = "Спасибо. Жалоба отправлена модератору."
        } catch {
            errorMessage = chatErrorMessage(for: error)
        }
    }

    func block(_ message: CommunityMessage) {
        blockedAuthors[message.authorID] = message.author
        saveBlockedAuthors()
        messages.removeAll { $0.authorID == message.authorID }
        confirmationMessage = "Пользователь «\(message.author)» заблокирован. Его сообщения больше не будут показываться."
    }

    func unblock(authorID: String) {
        blockedAuthors.removeValue(forKey: authorID)
        saveBlockedAuthors()
    }

    private func saveBlockedAuthors() {
        guard let data = try? JSONEncoder().encode(blockedAuthors) else { return }
        UserDefaults.standard.set(data, forKey: Self.blockedAuthorsKey)
    }

    private func chatErrorMessage(for error: Error) -> String {
        guard let cloudError = error as? CKError else {
            return "Проверь подключение к интернету и попробуй ещё раз."
        }

        switch cloudError.code {
        case .notAuthenticated:
            return "Чтобы писать в общий чат, войди в iCloud в настройках устройства."
        case .networkUnavailable, .networkFailure:
            return "Нет подключения к интернету. Попробуй ещё раз позже."
        case .permissionFailure:
            return "Для чата пока не настроены права CloudKit."
        default:
            return "Не удалось обновить чат. Попробуй ещё раз позже."
        }
    }
}

private struct CommunityChatView: View {
    @StateObject private var store = CommunityChatStore()
    @AppStorage("userName") private var userName = ""
    @AppStorage("communityChatAuthorID") private var chatAuthorID = ""
    @State private var draft = ""
    @State private var selectedReportMessage: CommunityMessage?
    @State private var showSafetyRules = false
    @FocusState private var isComposerFocused: Bool
    private let refreshTimer = Timer.publish(every: 12, on: .main, in: .common).autoconnect()

    private var displayName: String {
        let name = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Спортсмен" : name
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !store.isSending && !chatAuthorID.isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(colors: [Color(red: 0.04, green: 0.06, blue: 0.14), Color(red: 0.10, green: 0.08, blue: 0.24)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .ignoresSafeArea()
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            chatHeader
                            if store.isLoading && store.messages.isEmpty {
                                ProgressView().tint(.white).frame(maxWidth: .infinity).padding(.vertical, 42)
                            } else if store.messages.isEmpty {
                                ContentUnavailableView("Сообщений пока нет", systemImage: "bubble.left.and.bubble.right", description: Text("Напиши первым и начни разговор о тренировках."))
                                    .foregroundStyle(.white.opacity(0.72))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 42)
                            } else {
                                ForEach(store.messages) { message in
                                    CommunityMessageRow(
                                        message: message,
                                        chatAuthorID: chatAuthorID,
                                        store: store,
                                        selectedReportMessage: $selectedReportMessage
                                    )
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        .padding(.bottom, 88)
                    }
                    .refreshable { await store.loadMessages() }
                    .onChange(of: store.messages) { _, messages in
                        guard let lastMessage = messages.last else { return }
                        withAnimation { proxy.scrollTo(lastMessage.id, anchor: .bottom) }
                    }
                }
            }
            .navigationTitle("Общий чат")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showSafetyRules = true } label: {
                        Image(systemName: "hand.raised.fill")
                    }
                    .foregroundStyle(.white)
                    .accessibilityLabel("Правила и безопасность чата")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await store.loadMessages() } } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .foregroundStyle(.white)
                    .accessibilityLabel("Обновить сообщения")
                }
            }
            .safeAreaInset(edge: .bottom) { composer }
        }
        .tint(.mint)
        .task {
            if chatAuthorID.isEmpty { chatAuthorID = UUID().uuidString }
            await store.loadMessages()
        }
        .onReceive(refreshTimer) { _ in Task { await store.loadMessages(showProgress: false) } }
        .sheet(isPresented: $showSafetyRules) {
            CommunitySafetyView(blockedAuthors: store.blockedAuthors) { authorID in
                store.unblock(authorID: authorID)
            }
        }
        .confirmationDialog("Пожаловаться на сообщение?", isPresented: Binding(
            get: { selectedReportMessage != nil },
            set: { if !$0 { selectedReportMessage = nil } }
        ), titleVisibility: .visible) {
            ForEach(CommunityReportReason.allCases) { reason in
                Button(reason.rawValue) {
                    guard let message = selectedReportMessage else { return }
                    selectedReportMessage = nil
                    Task { await store.report(message: message, reason: reason, reporterID: chatAuthorID) }
                }
            }
            Button("Отмена", role: .cancel) { selectedReportMessage = nil }
        } message: {
            Text("Жалоба будет отправлена модератору вместе с текстом сообщения.")
        }
        .alert("Чат недоступен", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("Понятно", role: .cancel) { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
        .alert("Готово", isPresented: Binding(
            get: { store.confirmationMessage != nil },
            set: { if !$0 { store.confirmationMessage = nil } }
        )) {
            Button("Понятно", role: .cancel) { store.confirmationMessage = nil }
        } message: {
            Text(store.confirmationMessage ?? "")
        }
    }

    private var chatHeader: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("СООБЩЕСТВО", systemImage: "person.3.fill")
                .font(.caption.weight(.bold)).tracking(1.4).foregroundStyle(.mint)
            Text("Общайся, поддерживай и делись результатами.")
                .font(.subheadline).foregroundStyle(.white.opacity(0.72))
            Text("Сообщения видны всем пользователям Sport Tracker.")
                .font(.caption).foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(17)
        .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 21))
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Сообщение в общий чат", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .textInputAutocapitalization(.sentences)
                .autocorrectionDisabled(false)
                .focused($isComposerFocused)
                .foregroundStyle(.white)
                .padding(.horizontal, 15)
                .padding(.vertical, 11)
                .background(.white.opacity(0.11), in: RoundedRectangle(cornerRadius: 18))
            Button {
                let message = draft
                Task {
                    if await store.send(text: message, author: displayName, authorID: chatAuthorID) {
                        draft = ""
                        isComposerFocused = false
                    }
                }
            } label: {
                Image(systemName: store.isSending ? "hourglass" : "arrow.up")
                    .font(.headline.bold())
                    .foregroundStyle(canSend ? .black : .white.opacity(0.42))
                    .frame(width: 44, height: 44)
                    .background(canSend ? .mint : .white.opacity(0.12), in: Circle())
            }
            .disabled(!canSend)
            .accessibilityLabel("Отправить сообщение")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }
}

private struct CommunityMessageRow: View {
    let message: CommunityMessage
    let chatAuthorID: String
    @ObservedObject var store: CommunityChatStore
    @Binding var selectedReportMessage: CommunityMessage?

    private var isMine: Bool { message.authorID == chatAuthorID }

    var body: some View {
        CommunityMessageBubble(
            message: message,
            isMine: isMine,
            onReport: reportMessage,
            onBlock: blockMessage
        )
        .id(message.id)
    }

    private func reportMessage() {
        selectedReportMessage = message
    }

    private func blockMessage() {
        store.block(message)
    }
}

private struct CommunityMessageBubble: View {
    let message: CommunityMessage
    let isMine: Bool
    let onReport: () -> Void
    let onBlock: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isMine { Spacer(minLength: 44) }
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(message.author).font(.caption.weight(.bold)).foregroundStyle(isMine ? .black.opacity(0.72) : .mint)
                    if !isMine {
                        Menu {
                            Button("Пожаловаться", systemImage: "exclamationmark.bubble") { onReport() }
                            Button("Заблокировать пользователя", systemImage: "hand.raised.fill", role: .destructive) { onBlock() }
                        } label: {
                            Image(systemName: "ellipsis.circle").foregroundStyle(.white.opacity(0.52))
                        }
                        .accessibilityLabel("Действия с сообщением")
                    }
                }
                Text(message.text).font(.body).foregroundStyle(isMine ? .black : .white)
                Text(message.createdAt, style: .time).font(.caption2).foregroundStyle(isMine ? .black.opacity(0.55) : .white.opacity(0.48))
            }
            .padding(13)
            .background(isMine ? .mint : .white.opacity(0.10), in: RoundedRectangle(cornerRadius: 19))
            .frame(maxWidth: 300, alignment: isMine ? .trailing : .leading)
            if !isMine { Spacer(minLength: 44) }
        }
        .frame(maxWidth: .infinity, alignment: isMine ? .trailing : .leading)
    }
}

private struct CommunitySafetyView: View {
    @Environment(\.dismiss) private var dismiss
    let blockedAuthors: [String: String]
    let onUnblock: (String) -> Void

    var body: some View {
        NavigationStack {
            List {
                Section("Правила сообщества") {
                    Label("Общайся уважительно: без оскорблений, угроз и травли.", systemImage: "heart.text.square")
                    Label("Не публикуй личные данные, рекламу и спам.", systemImage: "person.crop.circle.badge.exclamationmark")
                    Label("Пожаловаться можно через меню ⋯ у сообщения.", systemImage: "exclamationmark.bubble")
                }
                Section("Поддержка") {
                    Text("Контакты поддержки опубликованы на странице Sport Tracker в App Store. Жалобы из чата передаются модератору.")
                }
                Section("Заблокированные пользователи") {
                    if blockedAuthors.isEmpty {
                        Text("Заблокированных пользователей нет.").foregroundStyle(.secondary)
                    } else {
                        ForEach(blockedAuthors.keys.sorted(), id: \.self) { authorID in
                            HStack {
                                Text(blockedAuthors[authorID] ?? "Пользователь")
                                Spacer()
                                Button("Разблокировать") { onUnblock(authorID) }
                                    .buttonStyle(.bordered)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Безопасность чата")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
        }
    }
}

private struct FoodCategoryChip: View {
    let title: String
    let systemIcon: String
    let tint: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: systemIcon).font(.body.weight(.semibold))
                Text(title).font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(isSelected ? .black : .white.opacity(0.78))
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(isSelected ? tint : .white.opacity(0.10), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct ProductCard: View {
    let product: FoodProduct

    var body: some View {
        NutritionProductRow(product: product)
    }
}

private struct ProductDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let product: FoodProduct

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(colors: [Color(red: 0.04, green: 0.06, blue: 0.14), Color(red: 0.10, green: 0.08, blue: 0.24)], startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
                VStack(alignment: .leading, spacing: 22) {
                    FoodProductIcon(product: product, size: 34)
                        .frame(width: 74, height: 74).background(product.category.tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 24))
                    Text(product.title).font(.largeTitle.bold()).foregroundStyle(.white)
                    Text("\(product.category.rawValue) · значения на 100 г").foregroundStyle(.white.opacity(0.65))
                    HStack(spacing: 9) {
                        RecipeNutrition(value: "\(product.calories)", title: "ккал", tint: .orange)
                        RecipeNutrition(value: "\(product.proteinText) г", title: "белки", tint: .cyan)
                        RecipeNutrition(value: "\(product.fatText) г", title: "жиры", tint: .pink)
                        RecipeNutrition(value: "\(product.carbsText) г", title: "углеводы", tint: .purple)
                    }
                    Text("Показатели приведены для базового продукта. Состав и калорийность готовых блюд, йогуртов с добавками, шоколада и других брендов могут отличаться.")
                        .font(.subheadline).foregroundStyle(.white.opacity(0.75)).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(20)
            }
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Готово") { dismiss() }.foregroundStyle(.white) } }
        }
    }
}

private struct WorkoutMascotView: View {
    let mascot: Mascot
    let type: WorkoutType
    let isRunning: Bool
    let isTired: Bool
    @State private var armsForward = false

    private var isInMotion: Bool { isRunning && !isTired }

    private var assetName: String {
        if type == .cycling { return isTired ? "FoxCyclingTired" : "FoxCycling" }
        return isTired ? "FoxRunningTired" : "FoxRunning"
    }

    private var frameInterval: TimeInterval { type == .cycling ? 0.28 : 0.18 }

    private func mascotAssetName(isAlternateFrame: Bool) -> String {
        if mascot == .fox { return assetName }

        let baseName: String
        switch (mascot, type) {
        case (.cat, .cycling): baseName = "CatCycling"
        case (.cat, _): baseName = "CatRunning"
        case (.dog, .cycling): baseName = "DogCycling"
        case (.dog, _): baseName = "DogRunning"
        case (.bunny, .cycling): baseName = "BunnyCycling"
        case (.bunny, _): baseName = "BunnyRunning"
        case (.fox, _): baseName = assetName
        }
        return isInMotion && isAlternateFrame ? "\(baseName)Alt" : baseName
    }

    var body: some View {
        ZStack {
            if isInMotion { speedLines }
            if mascot == .fox && isInMotion && type != .cycling {
                Image("FoxRunning")
                    .resizable()
                    .scaledToFit()
                    .opacity(armsForward ? 0 : 1)
                Image("FoxRunningAlt")
                    .resizable()
                    .scaledToFit()
                    .opacity(armsForward ? 1 : 0)
            } else if mascot == .fox {
                Image(assetName)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(isInMotion && type == .cycling ? 1.035 : 1)
                    .offset(y: isInMotion && type == .cycling ? -3 : 0)
                    .animation(.easeInOut(duration: 0.28).repeatForever(autoreverses: true), value: isInMotion)
            } else if isInMotion {
                TimelineView(.animation(minimumInterval: frameInterval, paused: false)) { context in
                    let frameNumber = Int(context.date.timeIntervalSinceReferenceDate / frameInterval)
                    Image(mascotAssetName(isAlternateFrame: frameNumber.isMultiple(of: 2)))
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(isInMotion ? 1.04 : 1)
                        .offset(y: isInMotion ? -3 : 0)
                        .opacity(isTired ? 0.72 : 1)
                }
            } else {
                Image(mascotAssetName(isAlternateFrame: false))
                    .resizable()
                    .scaledToFit()
                    .opacity(isTired ? 0.72 : 1)
            }
        }
        .onAppear { animate() }
        .onChange(of: isRunning) { _, _ in animate() }
        .onChange(of: isTired) { _, _ in animate() }
        .onChange(of: type) { _, _ in animate() }
        .accessibilityLabel(isTired ? "\(mascot.title) отдыхает после тренировки" : type == .cycling ? "\(mascot.title) быстро едет на велосипеде" : "\(mascot.title) быстро бежит")
    }

    private var speedLines: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                Capsule()
                    .fill(.cyan.opacity(0.48 - Double(index) * 0.10))
                    .frame(width: 34, height: 3)
                    .offset(x: -48, y: CGFloat(index - 1) * 23 + (type == .cycling ? 8 : 0))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func animate() {
        armsForward = false
        guard isInMotion && (mascot != .fox || type != .cycling) else { return }
        withAnimation(.easeInOut(duration: type == .cycling ? 0.28 : 0.24).repeatForever(autoreverses: true)) {
            armsForward = true
        }
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
    @AppStorage("selectedMascot") private var savedMascot = Mascot.fox.rawValue
    @State private var name = ""
    @State private var age = 25
    @State private var gender: Gender = .unspecified
    @State private var weight = 84.0
    @State private var height = 178.0
    @State private var mascot: Mascot = .fox

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
                    VStack(alignment: .leading, spacing: 12) {
                        Text("ВЫБЕРИ СВОЮ ЗВЕРЮШКУ").font(.caption.weight(.bold)).tracking(1.3).foregroundStyle(.cyan)
                        Text("Она будет твоим напарником во время тренировок.").font(.caption).foregroundStyle(.white.opacity(0.6))
                        HStack(spacing: 10) {
                            ForEach(Mascot.allCases) { candidate in
                                Button { mascot = candidate } label: {
                                    VStack(spacing: 4) {
                                        MascotPreviewView(mascot: candidate)
                                            .frame(width: 46, height: 42)
                                        Text(candidate.title).font(.caption2.weight(.semibold))
                                    }
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(mascot == candidate ? candidate.tint.opacity(0.65) : .white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(mascot == candidate ? .white.opacity(0.85) : .clear, lineWidth: 1.5))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Выбрать: \(candidate.title)")
                            }
                        }
                    }
                    .padding(18).background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 24))
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
                        savedName = name.trimmingCharacters(in: .whitespacesAndNewlines); savedAge = age; savedGender = gender.rawValue; savedWeight = weight; savedHeight = height; savedMascot = mascot.rawValue; profileComplete = true
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

private struct MascotPreviewView: View {
    let mascot: Mascot

    var body: some View {
        Image(mascot.previewAssetName)
            .resizable()
            .scaledToFit()
            .accessibilityHidden(true)
    }
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
