import SwiftData
import SwiftUI

// MARK: - PersonalRecordsView

@MainActor
struct PersonalRecordsView: View {

    let userId: String

    @Query(sort: \PersonalRecord.achievedAt, order: .reverse) private var records: [PersonalRecord]
    @State private var searchText = ""

    // MARK: Derived

    private var filteredRecords: [PersonalRecord] {
        guard !searchText.isEmpty else { return records }
        let query = searchText.lowercased()
        return records.filter { $0.exerciseName.lowercased().contains(query) }
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            ZStack {
                Color.kineticsBackground.ignoresSafeArea()

                if filteredRecords.isEmpty {
                    emptyState
                } else {
                    recordsList
                }
            }
            .navigationTitle("Personal Records")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Color.kineticsBackground, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search exercises"
            )
        }
    }

    // MARK: - Subviews

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "trophy.slash")
                .font(.system(size: 52, weight: .medium))
                .foregroundStyle(Color.kineticsSubtext)

            Text("No personal records yet")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)

            Text("Complete a workout to set your first PR.")
                .font(.subheadline)
                .foregroundStyle(Color.kineticsSubtext)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 40)
    }

    private var recordsList: some View {
        List {
            ForEach(filteredRecords) { record in
                PRDetailRow(record: record)
                    .listRowBackground(Color.kineticsDark)
                    .listRowSeparatorTint(Color.kineticsSubtext.opacity(0.25))
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }
}

// MARK: - PRDetailRow

private struct PRDetailRow: View {

    let record: PersonalRecord

    // MARK: Body

    var body: some View {
        HStack(spacing: 14) {
            // Trophy icon badge
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.kineticsAmber.opacity(0.12))
                    .frame(width: 40, height: 40)

                Image(systemName: "trophy.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.kineticsAmber)
            }

            // Exercise info
            VStack(alignment: .leading, spacing: 3) {
                Text(record.exerciseName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text("\(record.reps) reps")
                    .font(.caption)
                    .foregroundStyle(Color.kineticsSubtext)
            }

            Spacer()

            // Weight + date
            VStack(alignment: .trailing, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(weightFormatted(record.weight))
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                        .monospacedDigit()

                    Text("kg")
                        .font(.caption)
                        .foregroundStyle(Color.kineticsSubtext)
                }

                Text(record.achievedAt, format: .dateTime.month(.abbreviated).day())
                    .font(.caption)
                    .foregroundStyle(Color.kineticsSubtext)
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: Helpers

    private func weightFormatted(_ weight: Double) -> String {
        weight.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", weight)
            : String(format: "%.1f", weight)
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
                AddMeasurementSheet(userId: userId) {
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
                value: latestWeight > 0 ? weightFormatted(latestWeight) : "--",
                unit: latestWeight > 0 ? "kg" : nil
            )
            MeasurementStatCard(
                label: "BODY FAT",
                value: latestBodyFat > 0 ? String(format: "%.1f", latestBodyFat) : "--",
                unit: latestBodyFat > 0 ? "%" : nil
            )
        }
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
                MeasurementRow(measurement: measurement)
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

// MARK: - MeasurementRow

private struct MeasurementRow: View {

    let measurement: BodyMeasurement

    var body: some View {
        HStack(spacing: 12) {
            // Date column
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

            // Metrics column
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
    let onSave: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var weightText = ""
    @State private var bodyFatText = ""
    @State private var notes = ""

    // MARK: Computed

    private var canSave: Bool {
        !weightText.isEmpty || !bodyFatText.isEmpty
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Weight")
                            .foregroundStyle(.white)
                        Spacer()
                        TextField("0.0", text: $weightText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(.white)
                        Text("kg")
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
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(Color.kineticsSubtext)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        saveMeasurement()
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(canSave ? Color.kineticsBlue : Color.kineticsSubtext)
                    .disabled(!canSave)
                }
            }
        }
    }

    // MARK: Save

    private func saveMeasurement() {
        let parsedWeight = Double(weightText.replacingOccurrences(of: ",", with: ".")) ?? 0
        let parsedBodyFat = Double(bodyFatText.replacingOccurrences(of: ",", with: ".")) ?? 0

        let measurement = BodyMeasurement(
            userId: userId,
            recordedAt: Date(),
            weightKg: parsedWeight,
            bodyFatPercent: parsedBodyFat,
            notes: notes
        )

        modelContext.insert(measurement)
        try? modelContext.save()
        onSave()
        dismiss()
    }
}
