import SwiftUI

struct ChatWorkoutVisualizationMessageCard: View {
    let model: ChatHealthWorkoutModel

    @State private var expandedIDs: Set<String>

    init(model: ChatHealthWorkoutModel) {
        self.model = model
        let sorted = model.workouts.sorted { $0.start < $1.start }
        if sorted.count == 1, let first = sorted.first {
            _expandedIDs = State(initialValue: [first.id])
        } else {
            _expandedIDs = State(initialValue: [])
        }
    }

    private var workouts: [ChatHealthWorkoutModel.WorkoutSession] {
        model.workouts.sorted { $0.start < $1.start }
    }

    private var totalDurationMinutes: Double {
        workouts.reduce(0.0) { $0 + Double($1.elapsedSeconds) / 60 }
    }

    private var totalDistanceMeters: Double {
        workouts.compactMap(\.distanceMeters).reduce(0, +)
    }

    private var totalEnergyKcal: Double {
        workouts.compactMap(\.activeEnergyKcal).reduce(0, +)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if workouts.isEmpty {
                Text(L10n.text("health.tool.error.no_workouts", fallback: "No matching workout records found."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                summaryGrid

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(workouts.prefix(20)) { workout in
                        ChatWorkoutSessionRow(
                            workout: workout,
                            isExpanded: Binding(
                                get: { expandedIDs.contains(workout.id) },
                                set: { expanded in
                                    if expanded {
                                        expandedIDs.insert(workout.id)
                                    } else {
                                        expandedIDs.remove(workout.id)
                                    }
                                }
                            )
                        )
                    }
                }

                if workouts.count > 20 {
                    Text(L10n.format("chat.workout.more_format", fallback: "%d more sessions", workouts.count - 20))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if model.notes.isEmpty == false {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(model.notes, id: \.self) { note in
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            HealthKitDataSourceAttribution()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "figure.run")
                .font(.headline)
                .foregroundStyle(Color.accentColor)
            Text(L10n.text("chat.workout.title", fallback: "Workout Data"))
                .font(.headline)
            Spacer()
            Text("\(workouts.count)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.primary.opacity(0.06), in: Capsule())
        }
    }

    private var summaryGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            ChatWorkoutMetricTile(
                title: L10n.text("chat.workout.metric.sessions", fallback: "Sessions"),
                value: "\(workouts.count)",
                icon: "list.bullet.rectangle"
            )
            ChatWorkoutMetricTile(
                title: L10n.text("chat.workout.metric.duration", fallback: "Duration"),
                value: ChatHealthWorkoutModel.formatDurationMinutes(totalDurationMinutes),
                icon: "clock"
            )
            ChatWorkoutMetricTile(
                title: L10n.text("chat.workout.metric.distance", fallback: "Distance"),
                value: ChatHealthWorkoutModel.formatDistanceMeters(totalDistanceMeters),
                icon: "location"
            )
            ChatWorkoutMetricTile(
                title: L10n.text("chat.workout.metric.energy", fallback: "Energy"),
                value: String(format: "%.0f kcal", totalEnergyKcal),
                icon: "flame"
            )
        }
    }
}

private struct ChatWorkoutMetricTile: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 24, height: 24)
                .background(Color.accentColor.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct ChatWorkoutSessionRow: View {
    let workout: ChatHealthWorkoutModel.WorkoutSession
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.snappy(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: iconName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(activityColor, in: Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text(workout.activityTypeName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(workout.startText ?? "")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(ChatHealthWorkoutModel.formatDurationMinutes(Double(workout.elapsedSeconds) / 60))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        if let distance = workout.distanceMeters, distance > 0 {
                            Text(ChatHealthWorkoutModel.formatDistanceMeters(distance))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    detailMetrics

                    if workout.heartRateSamples.isEmpty == false {
                        ChatWorkoutHeartRateStrip(samples: workout.heartRateSamples)
                    }

                    if workout.route.count > 1 {
                        ChatWorkoutRoutePreview(points: workout.route)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(10)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var detailMetrics: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 6)], alignment: .leading, spacing: 6) {
            ForEach(detailChips, id: \.text) { chip in
                ChatWorkoutChip(icon: chip.icon, text: chip.text)
            }
        }
    }

    private var detailChips: [(icon: String, text: String)] {
        var chips: [(String, String)] = []
        if let energy = workout.activeEnergyKcal, energy > 0 {
            chips.append(("flame", String(format: "%.0f kcal", energy)))
        }
        if let heartRate = workout.averageHeartRateBpm, heartRate > 0 {
            chips.append(("heart", String(format: "%.0f bpm", heartRate)))
        }
        if let pace = workout.averagePaceMinPerKm, pace > 0 {
            chips.append(("speedometer", formatPace(pace)))
        }
        if let speed = workout.averageSpeedMps, speed > 0 {
            chips.append(("gauge.with.dots.needle.33percent", String(format: "%.1f km/h", speed * 3.6)))
        }
        return chips
    }

    private var iconName: String {
        switch workout.activityTypeKey {
        case "running": return "figure.run"
        case "walking": return "figure.walk"
        case "cycling": return "bicycle"
        case "hiking": return "figure.hiking"
        case "swimming": return "figure.pool.swim"
        case "yoga", "pilates": return "figure.mind.and.body"
        default: return "figure.strengthtraining.traditional"
        }
    }

    private var activityColor: Color {
        switch workout.activityTypeKey {
        case "running": return .orange
        case "walking": return .green
        case "cycling": return .blue
        case "swimming": return .cyan
        case "hiking": return .brown
        default: return .purple
        }
    }

    private func formatPace(_ pace: Double) -> String {
        let minutes = Int(pace)
        let seconds = Int(((pace - Double(minutes)) * 60).rounded())
        return String(format: "%d'%02d\"/km", minutes, seconds)
    }
}

private struct ChatWorkoutChip: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text(text)
                .lineLimit(1)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.primary.opacity(0.06), in: Capsule())
    }
}

private struct ChatWorkoutHeartRateStrip: View {
    let samples: [ChatHealthWorkoutModel.HeartRatePoint]

    private var bins: [ChatHealthWorkoutModel.HeartRateBin] {
        ChatHealthWorkoutModel.binHeartRates(samples: samples, maxBins: 28)
    }

    private var maxBpm: Double {
        max(1, bins.map(\.max).max() ?? 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(L10n.text("chat.workout.heart_rate", fallback: "Heart rate"), systemImage: "heart")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if let average = averageBpm {
                    Text(String(format: "%.0f bpm", average))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(alignment: .bottom, spacing: 2) {
                ForEach(Array(bins.enumerated()), id: \.offset) { _, bin in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(bin.isEmpty ? Color.primary.opacity(0.08) : Color.red.opacity(0.65))
                        .frame(height: bin.isEmpty ? 5 : max(8, CGFloat(bin.max / maxBpm) * 44))
                }
            }
            .frame(height: 48, alignment: .bottom)
        }
        .padding(8)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var averageBpm: Double? {
        guard samples.isEmpty == false else { return nil }
        return samples.map(\.bpm).reduce(0, +) / Double(samples.count)
    }
}

private struct ChatWorkoutRoutePreview: View {
    let points: [ChatHealthWorkoutModel.RoutePoint]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(L10n.text("chat.workout.route", fallback: "Route"), systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            GeometryReader { proxy in
                let path = routePath(in: proxy.size)
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.blue.opacity(0.08))
                    path
                        .stroke(Color.blue, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    if let first = normalizedPoints(in: proxy.size).first {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 7, height: 7)
                            .position(first)
                    }
                    if let last = normalizedPoints(in: proxy.size).last {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 7, height: 7)
                            .position(last)
                    }
                }
            }
            .frame(height: 86)
        }
        .padding(8)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func routePath(in size: CGSize) -> Path {
        var path = Path()
        let normalized = normalizedPoints(in: size)
        guard let first = normalized.first else { return path }
        path.move(to: first)
        for point in normalized.dropFirst() {
            path.addLine(to: point)
        }
        return path
    }

    private func normalizedPoints(in size: CGSize) -> [CGPoint] {
        guard points.isEmpty == false else { return [] }
        let minLat = points.map(\.lat).min() ?? 0
        let maxLat = points.map(\.lat).max() ?? 1
        let minLon = points.map(\.lon).min() ?? 0
        let maxLon = points.map(\.lon).max() ?? 1
        let latSpan = max(0.000001, maxLat - minLat)
        let lonSpan = max(0.000001, maxLon - minLon)
        let inset: CGFloat = 12
        let width = max(1, size.width - inset * 2)
        let height = max(1, size.height - inset * 2)

        return points.map { point in
            CGPoint(
                x: inset + CGFloat((point.lon - minLon) / lonSpan) * width,
                y: inset + CGFloat(1 - (point.lat - minLat) / latSpan) * height
            )
        }
    }
}
