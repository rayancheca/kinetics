import Charts
import SwiftData
import SwiftUI

// MARK: - PRFilter

private enum PRFilter: String, CaseIterable {
    case byMuscle = "By Muscle"
    case byExercise = "By Exercise"
    case all = "All"
}

// MARK: - PersonalRecordsView

@MainActor
struct PersonalRecordsView: View {

    let userId: String

    @Query(sort: \PersonalRecord.achievedAt, order: .reverse) private var allRecords: [PersonalRecord]
    @Query(sort: \Exercise.name, order: .forward) private var exercises: [Exercise]

    @State private var filter: PRFilter = .all
    @State private var searchText = ""

    // MARK: Derived

    private var userRecords: [PersonalRecord] {
        allRecords.filter { $0.userId == userId }
    }

    private var filteredRecords: [PersonalRecord] {
        let base = searchText.isEmpty
            ? userRecords
            : userRecords.filter { $0.exerciseName.lowercased().contains(searchText.lowercased()) }

        switch filter {
        case .all, .byExercise:
            return base.sorted { $0.exerciseName < $1.exerciseName }
        case .byMuscle:
            return base.sorted { muscleFor($0) < muscleFor($1) }
        }
    }

    private var groupedByMuscle: [(muscle: String, records: [PersonalRecord])] {
        let grouped = Dictionary(grouping: filteredRecords) { muscleFor($0) }
        return grouped
            .sorted { $0.key < $1.key }
            .map { (muscle: $0.key, records: $0.value.sorted { $0.exerciseName < $1.exerciseName }) }
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            ZStack {
                Color.kineticsBackground.ignoresSafeArea()

                VStack(spacing: 0) {
                    filterPicker
                    Divider()
                        .background(Color.kineticsSubtext.opacity(0.15))

                    if filteredRecords.isEmpty {
                        emptyState
                    } else {
                        recordsContent
                    }
                }
            }
            .navigationTitle("Personal Records")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Color.kineticsBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search exercises"
            )
        }
    }

    // MARK: - Filter Picker

    private var filterPicker: some View {
        Picker("Filter", selection: $filter) {
            ForEach(PRFilter.allCases, id: \.self) { option in
                Text(option.rawValue).tag(option)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.kineticsBackground)
    }

    // MARK: - Records Content

    @ViewBuilder
    private var recordsContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 16) {
                if filter == .byMuscle {
                    ForEach(groupedByMuscle, id: \.muscle) { group in
                        muscleSectionHeader(group.muscle)
                        ForEach(group.records, id: \.id) { record in
                            PRCard(record: record, exercises: exercises)
                        }
                    }
                } else {
                    ForEach(filteredRecords, id: \.id) { record in
                        PRCard(record: record, exercises: exercises)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 32)
        }
    }

    private func muscleSectionHeader(_ muscle: String) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.kineticsAmber)
                .frame(width: 3, height: 16)

            Text(muscle.uppercased())
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.kineticsAmber)
                .tracking(1.2)
        }
        .padding(.top, 8)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.kineticsAmber.opacity(0.08))
                    .frame(width: 96, height: 96)
                Image(systemName: "trophy.fill")
                    .font(.system(size: 44, weight: .medium))
                    .foregroundStyle(Color.kineticsAmber.opacity(0.5))
            }

            VStack(spacing: 8) {
                Text(searchText.isEmpty ? "No personal records yet" : "No results")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)

                Text(searchText.isEmpty
                     ? "Complete a workout and log your sets to\nset your first PR automatically."
                     : "Try a different search term.")
                    .font(.subheadline)
                    .foregroundStyle(Color.kineticsSubtext)
                    .multilineTextAlignment(.center)
            }

            Spacer()
        }
        .padding(.horizontal, 40)
    }

    // MARK: - Helpers

    private func muscleFor(_ record: PersonalRecord) -> String {
        exercises.first { $0.id == record.exerciseId }?.primaryMuscle ?? "Other"
    }
}

// MARK: - PRCard

private struct PRCard: View {

    let record: PersonalRecord
    let exercises: [Exercise]

    private var muscle: String {
        exercises.first { $0.id == record.exerciseId }?.primaryMuscle ?? "Other"
    }

    private var weightDisplay: String {
        record.weight.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", record.weight)
            : String(format: "%.1f", record.weight)
    }

    var body: some View {
        NavigationLink(destination: PRDetailView(record: record)) {
            cardContent
        }
        .buttonStyle(.plain)
    }

    private var cardContent: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 0) {
                // Top row: exercise name + muscle chip
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(record.exerciseName)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(2)

                        Text(muscle)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.kineticsAmber)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill(Color.kineticsAmber.opacity(0.12))
                            )
                    }
                    Spacer()
                }
                .padding(.bottom, 16)

                // Weight display — big amber number
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(weightDisplay)
                        .font(.system(size: 52, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.kineticsAmber)
                        .monospacedDigit()

                    Text("kg")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color.kineticsAmber.opacity(0.6))
                        .padding(.bottom, 6)
                }

                // Reps + date row
                HStack(spacing: 16) {
                    Label("× \(record.reps) reps", systemImage: "repeat")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.kineticsSubtext)

                    Label(
                        record.achievedAt.formatted(.dateTime.month(.wide).day().year()),
                        systemImage: "calendar"
                    )
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.kineticsSubtext)
                    .lineLimit(1)
                }
                .padding(.top, 10)

                Divider()
                    .background(Color.kineticsSubtext.opacity(0.15))
                    .padding(.vertical, 12)

                // Bottom row: estimated 1RM + share
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("EST. 1RM")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.kineticsSubtext)
                            .tracking(0.8)

                        Text(estimated1RM)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.kineticsGreen)
                    }

                    Spacer()

                    // Share button
                    Button {
                        ShareCardGenerator.share(record: record)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Share")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundStyle(Color.kineticsBlue)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.kineticsBlue.opacity(0.12))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
        }
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.kineticsDark)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.kineticsAmber.opacity(0.15), lineWidth: 1)
                )
        )
    }

    private var estimated1RM: String {
        guard record.reps > 0 else { return "--" }
        let oneRM = record.weight * (1 + Double(record.reps) / 30.0)
        return oneRM.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(oneRM)) kg"
            : String(format: "%.1f kg", oneRM)
    }
}

// MARK: - PRDetailView

struct PRDetailView: View {

    let record: PersonalRecord

    @Query(sort: \PersonalRecord.achievedAt, order: .forward) private var allRecords: [PersonalRecord]

    /// All PRs for the same exercise, used to simulate history
    /// (in the real model one PR per exercise is stored — we show what we have)
    private var historyRecords: [PersonalRecord] {
        allRecords.filter { $0.exerciseId == record.exerciseId }
    }

    var body: some View {
        ZStack {
            Color.kineticsBackground.ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    headerSection
                    prHighlight
                    progressChartSection
                    historyListSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle(record.exerciseName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.kineticsBackground, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    ShareCardGenerator.share(record: record)
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.kineticsBlue)
                }
            }
        }
    }

    // MARK: - Subviews

    private var headerSection: some View {
        HStack(spacing: 10) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Color.kineticsAmber)
                .frame(width: 44, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.kineticsAmber.opacity(0.12))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text("Personal Record")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.kineticsAmber)
                    .tracking(0.5)

                Text(record.exerciseName)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
            }

            Spacer()
        }
    }

    private var prHighlight: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("BEST WEIGHT")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.kineticsSubtext)
                .tracking(1.2)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(weightDisplay)
                    .font(.system(size: 64, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.kineticsAmber)
                    .monospacedDigit()

                VStack(alignment: .leading, spacing: 2) {
                    Text("kg")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Color.kineticsAmber.opacity(0.6))

                    Text("× \(record.reps) reps")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.kineticsSubtext)
                }
                .padding(.bottom, 8)
            }

            HStack(spacing: 20) {
                metaStat(
                    label: "Achieved",
                    value: record.achievedAt.formatted(.dateTime.month(.abbreviated).day().year())
                )
                metaStat(
                    label: "Est. 1RM",
                    value: estimated1RM
                )
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.kineticsDark)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.kineticsAmber.opacity(0.2), lineWidth: 1)
                )
        )
    }

    private func metaStat(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.kineticsSubtext)
                .tracking(0.8)

            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
    }

    private var progressChartSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("PROGRESSION")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.kineticsSubtext)
                .tracking(1.2)

            if historyRecords.count < 2 {
                insufficientDataState
            } else {
                PRHistoryChart(records: historyRecords)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.kineticsDark)
        )
    }

    private var insufficientDataState: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(Color.kineticsAmber.opacity(0.35))

            Text("Log more sessions to see progress")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.kineticsSubtext)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 160)
    }

    private var historyListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("HISTORY")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.kineticsSubtext)
                .tracking(1.2)

            if historyRecords.isEmpty {
                Text("No history available.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.kineticsSubtext)
                    .padding(.top, 4)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(historyRecords.reversed(), id: \.id) { entry in
                        PRHistoryRow(entry: entry, isCurrent: entry.id == record.id)
                    }
                }
            }
        }
    }

    // MARK: Helpers

    private var weightDisplay: String {
        record.weight.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", record.weight)
            : String(format: "%.1f", record.weight)
    }

    private var estimated1RM: String {
        guard record.reps > 0 else { return "--" }
        let oneRM = record.weight * (1 + Double(record.reps) / 30.0)
        return oneRM.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(oneRM)) kg"
            : String(format: "%.1f kg", oneRM)
    }
}

// MARK: - PRHistoryChart

private struct PRHistoryChart: View {

    let records: [PersonalRecord]

    var body: some View {
        Chart(records, id: \.id) { record in
            // Area fill
            AreaMark(
                x: .value("Date", record.achievedAt),
                y: .value("Weight (kg)", record.weight)
            )
            .foregroundStyle(
                LinearGradient(
                    colors: [
                        Color.kineticsAmber.opacity(0.22),
                        Color.kineticsAmber.opacity(0.03)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .interpolationMethod(.catmullRom)

            // Line
            LineMark(
                x: .value("Date", record.achievedAt),
                y: .value("Weight (kg)", record.weight)
            )
            .foregroundStyle(Color.kineticsAmber)
            .lineStyle(StrokeStyle(lineWidth: 2.5))
            .interpolationMethod(.catmullRom)

            // Data point circle
            PointMark(
                x: .value("Date", record.achievedAt),
                y: .value("Weight (kg)", record.weight)
            )
            .foregroundStyle(Color.kineticsAmber)
            .symbolSize(60)

            PointMark(
                x: .value("Date", record.achievedAt),
                y: .value("Weight (kg)", record.weight)
            )
            .foregroundStyle(Color.kineticsDark)
            .symbolSize(18)
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                    .foregroundStyle(Color.kineticsSubtext.opacity(0.2))
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(date, format: .dateTime.month(.abbreviated).day())
                            .font(.system(size: 10))
                            .foregroundStyle(Color.kineticsSubtext)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                    .foregroundStyle(Color.kineticsSubtext.opacity(0.2))
                AxisValueLabel {
                    if let kg = value.as(Double.self) {
                        Text("\(Int(kg)) kg")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.kineticsSubtext)
                    }
                }
            }
        }
        .chartPlotStyle { plot in
            plot.background(Color.clear)
        }
        .frame(height: 200)
    }
}

// MARK: - PRHistoryRow

private struct PRHistoryRow: View {

    let entry: PersonalRecord
    let isCurrent: Bool

    private var weightText: String {
        entry.weight.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(entry.weight)) kg"
            : String(format: "%.1f kg", entry.weight)
    }

    var body: some View {
        HStack(spacing: 12) {
            // Date
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.achievedAt, format: .dateTime.month(.abbreviated).day().year())
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)

                if isCurrent {
                    Text("Current PR")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.kineticsAmber)
                }
            }

            Spacer()

            // Weight
            Text(weightText)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(isCurrent ? Color.kineticsAmber : .white)
                .monospacedDigit()

            // Reps
            Text("× \(entry.reps)")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.kineticsSubtext)
                .frame(width: 40, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isCurrent
                      ? Color.kineticsAmber.opacity(0.08)
                      : Color.kineticsMidGray)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(
                            isCurrent ? Color.kineticsAmber.opacity(0.25) : Color.clear,
                            lineWidth: 1
                        )
                )
        )
    }
}

// MARK: - BodyMeasurementView

@MainActor
struct BodyMeasurementView: View {

    let userId: String

    @Query(sort: \BodyMeasurement.recordedAt, order: .reverse) private var measurements: [BodyMeasurement]
    @Environment(\.modelContext) private var modelContext
    @State private var showAddSheet = false
    @State private var latestWeight: Double = 0
    @State private var latestBodyFat: Double = 0
    /// Whether the user prefers imperial (lbs) vs metric (kg) display.
    @State private var showImperial = false

    // MARK: Body

    var body: some View {
        NavigationStack {
            ZStack {
                Color.kineticsBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        statCards
                        historySection
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Body Stats")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Color.kineticsBackground, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    let unitLabel = showImperial ? "lbs" : "kg"
                    Button {
                        showImperial.toggle()
                    } label: {
                        Text(unitLabel)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.kineticsBlue)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(Color.kineticsBlue.opacity(0.15)))
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Color.kineticsBlue)
                    }
                }
            }
            .onAppear {
                latestWeight = measurements.first?.weightKg ?? 0
                latestBodyFat = measurements.first?.bodyFatPercent ?? 0
            }
            .onChange(of: measurements) { _, newValue in
                latestWeight = newValue.first?.weightKg ?? 0
                latestBodyFat = newValue.first?.bodyFatPercent ?? 0
            }
            .sheet(isPresented: $showAddSheet) {
                AddMeasurementSheet(userId: userId, showImperial: showImperial) {
                    showAddSheet = false
                }
            }
        }
    }

    // MARK: - Subviews

    private var statCards: some View {
        HStack(spacing: 12) {
            MeasurementStatCard(
                label: "WEIGHT",
                value: latestWeight > 0 ? displayWeight(latestWeight) : "--",
                unit: latestWeight > 0 ? (showImperial ? "lbs" : "kg") : nil
            )
            MeasurementStatCard(
                label: "BODY FAT",
                value: latestBodyFat > 0 ? String(format: "%.1f", latestBodyFat) : "--",
                unit: latestBodyFat > 0 ? "%" : nil
            )
        }
    }

    // MARK: - Unit Helpers

    private func displayWeight(_ kg: Double) -> String {
        if showImperial {
            let lbs = kg * 2.20462
            return lbs.truncatingRemainder(dividingBy: 1) == 0
                ? String(format: "%.0f", lbs)
                : String(format: "%.1f", lbs)
        }
        return weightFormatted(kg)
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("HISTORY")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.kineticsSubtext)
                .tracking(1.2)
                .padding(.leading, 4)

            if measurements.isEmpty {
                measurementEmptyState
            } else {
                measurementList
            }
        }
    }

    private var measurementEmptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "person.bust")
                .font(.system(size: 44, weight: .medium))
                .foregroundStyle(Color.kineticsSubtext)

            Text("No measurements yet")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)

            Text("Log your first body measurement.")
                .font(.subheadline)
                .foregroundStyle(Color.kineticsSubtext)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var measurementList: some View {
        LazyVStack(spacing: 0) {
            ForEach(measurements) { measurement in
                BMeasurementRow(measurement: measurement)
                    .background(Color.kineticsDark)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            deleteMeasurement(measurement)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }

                if measurement.id != measurements.last?.id {
                    Divider()
                        .background(Color.kineticsSubtext.opacity(0.2))
                        .padding(.leading, 16)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: Helpers

    private func deleteMeasurement(_ measurement: BodyMeasurement) {
        modelContext.delete(measurement)
        try? modelContext.save()
    }

    private func weightFormatted(_ weight: Double) -> String {
        weight.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", weight)
            : String(format: "%.1f", weight)
    }
}

// MARK: - MeasurementStatCard

private struct MeasurementStatCard: View {

    let label: String
    let value: String
    let unit: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.kineticsSubtext)
                .tracking(1.1)

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()

                if let unit {
                    Text(unit)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.kineticsSubtext)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.kineticsDark, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - BMeasurementRow (renamed to avoid conflict with GymProgressView private struct)

private struct BMeasurementRow: View {

    let measurement: BodyMeasurement

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(measurement.recordedAt, format: .dateTime.month(.abbreviated).day().year())
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)

                if !measurement.notes.isEmpty {
                    Text(measurement.notes)
                        .font(.caption)
                        .foregroundStyle(Color.kineticsSubtext)
                        .lineLimit(1)
                }
            }

            Spacer()

            HStack(spacing: 16) {
                if measurement.weightKg > 0 {
                    MetricPill(
                        value: weightFormatted(measurement.weightKg),
                        unit: "kg",
                        color: Color.kineticsBlue
                    )
                }

                if measurement.bodyFatPercent > 0 {
                    MetricPill(
                        value: String(format: "%.1f", measurement.bodyFatPercent),
                        unit: "%",
                        color: Color.kineticsGreen
                    )
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func weightFormatted(_ weight: Double) -> String {
        weight.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", weight)
            : String(format: "%.1f", weight)
    }
}

// MARK: - MetricPill

private struct MetricPill: View {

    let value: String
    let unit: String
    let color: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(color)
                .monospacedDigit()

            Text(unit)
                .font(.caption)
                .foregroundStyle(color.opacity(0.7))
        }
    }
}

// MARK: - AddMeasurementSheet

private struct AddMeasurementSheet: View {

    let userId: String
    let showImperial: Bool
    let onSave: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var weightText = ""
    @State private var bodyFatText = ""
    @State private var notes = ""
    @State private var useImperial: Bool

    // MARK: Init

    init(userId: String, showImperial: Bool = false, onSave: @escaping () -> Void) {
        self.userId = userId
        self.showImperial = showImperial
        self.onSave = onSave
        self._useImperial = State(initialValue: showImperial)
    }

    // MARK: Computed

    private var canSave: Bool {
        !weightText.isEmpty || !bodyFatText.isEmpty
    }

    private var weightUnit: String { useImperial ? "lbs" : "kg" }

    // MARK: Body

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Unit")
                            .foregroundStyle(.white)
                        Spacer()
                        Picker("", selection: $useImperial) {
                            Text("kg").tag(false)
                            Text("lbs").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 120)
                        .tint(Color.kineticsBlue)
                    }
                } header: {
                    Text("Preferences")
                        .foregroundStyle(Color.kineticsSubtext)
                }
                .listRowBackground(Color.kineticsDark)

                Section {
                    HStack {
                        Text("Weight")
                            .foregroundStyle(.white)
                        Spacer()
                        TextField("0.0", text: $weightText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(.white)
                        Text(weightUnit)
                            .foregroundStyle(Color.kineticsSubtext)
                    }

                    HStack {
                        Text("Body Fat")
                            .foregroundStyle(.white)
                        Spacer()
                        TextField("0.0", text: $bodyFatText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(.white)
                        Text("%")
                            .foregroundStyle(Color.kineticsSubtext)
                    }
                } header: {
                    Text("Measurements")
                        .foregroundStyle(Color.kineticsSubtext)
                }
                .listRowBackground(Color.kineticsDark)

                Section {
                    TextField("Optional note…", text: $notes, axis: .vertical)
                        .foregroundStyle(.white)
                        .lineLimit(3, reservesSpace: false)
                } header: {
                    Text("Notes")
                        .foregroundStyle(Color.kineticsSubtext)
                }
                .listRowBackground(Color.kineticsDark)
            }
            .scrollContentBackground(.hidden)
            .background(Color.kineticsBackground)
            .navigationTitle("Log Measurement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.kineticsBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.kineticsSubtext)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { saveMeasurement() }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(canSave ? Color.kineticsBlue : Color.kineticsSubtext)
                        .disabled(!canSave)
                }
            }
        }
    }

    // MARK: Save

    private func saveMeasurement() {
        let rawWeight = Double(weightText.replacingOccurrences(of: ",", with: ".")) ?? 0
        let parsedBodyFat = Double(bodyFatText.replacingOccurrences(of: ",", with: ".")) ?? 0
        let weightKg = useImperial ? rawWeight / 2.20462 : rawWeight

        let measurement = BodyMeasurement(
            userId: userId,
            recordedAt: Date(),
            weightKg: weightKg,
            bodyFatPercent: parsedBodyFat,
            notes: notes
        )

        modelContext.insert(measurement)
        try? modelContext.save()
        onSave()
        dismiss()
    }
}
