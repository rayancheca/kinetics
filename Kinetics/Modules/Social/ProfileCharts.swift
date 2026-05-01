import Charts
import SwiftUI

// MARK: - TrainingFrequencyChart

struct TrainingFrequencyChart: View {

    let workoutCount: Int

    private var weekData: [(day: String, count: Int)] {
        let days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        let counts = [1, 0, 2, 1, 1, 0, 1]
        return zip(days, counts).map { (day: $0, count: $1) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TRAINING FREQUENCY")
                .font(.system(size: 10, weight: .semibold)).tracking(2.0)
                .foregroundStyle(.white.opacity(0.38))

            Chart(weekData, id: \.day) { entry in
                BarMark(x: .value("Day", entry.day), y: .value("Sessions", entry.count))
                    .foregroundStyle(LinearGradient(
                        colors: [Color.kineticsBlue, Color.kineticsBlue.opacity(0.5)],
                        startPoint: .top, endPoint: .bottom
                    ))
                    .cornerRadius(4)
            }
            .chartXAxis {
                AxisMarks(values: .automatic) { _ in
                    AxisValueLabel().foregroundStyle(Color.kineticsSubtext).font(.system(size: 10))
                }
            }
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                    AxisValueLabel().foregroundStyle(Color.kineticsSubtext).font(.system(size: 10))
                    AxisGridLine().foregroundStyle(.white.opacity(0.05))
                }
            }
            .frame(height: 120)
        }
        .padding(16)
        .background(Color.kineticsDark)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - VolumeOverTimeChart

struct VolumeOverTimeChart: View {

    let workoutCount: Int

    private var volumeData: [(day: Int, volume: Double)] {
        (0..<30).map { day in (day: day, volume: Double(day) * 1.2 + Double(day % 5) * 0.5) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("VOLUME LAST 30 DAYS")
                .font(.system(size: 10, weight: .semibold)).tracking(2.0)
                .foregroundStyle(.white.opacity(0.38))

            Chart(volumeData, id: \.day) { entry in
                AreaMark(x: .value("Day", entry.day), y: .value("Volume", max(0, entry.volume)))
                    .foregroundStyle(LinearGradient(
                        colors: [Color.kineticsGreen.opacity(0.4), Color.kineticsGreen.opacity(0.0)],
                        startPoint: .top, endPoint: .bottom
                    ))
                LineMark(x: .value("Day", entry.day), y: .value("Volume", max(0, entry.volume)))
                    .foregroundStyle(Color.kineticsGreen)
                    .lineStyle(StrokeStyle(lineWidth: 2))
            }
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                    AxisValueLabel().foregroundStyle(Color.kineticsSubtext).font(.system(size: 10))
                    AxisGridLine().foregroundStyle(.white.opacity(0.05))
                }
            }
            .frame(height: 100)
        }
        .padding(16)
        .background(Color.kineticsDark)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - TopSportsChart

struct TopSportsChart: View {

    let activities: [FeedItem]

    private var sportBreakdown: [(sport: String, count: Int)] {
        var counts: [String: Int] = [:]
        for item in activities { counts[item.activityType, default: 0] += 1 }
        let total = max(1, counts.values.reduce(0, +))
        return counts.sorted { $0.value > $1.value }.prefix(4)
            .map { (sport: $0.key, count: $0.value * 100 / total) }
    }

    private var fallbackData: [(sport: String, count: Int)] {
        [("Striking", 40), ("Iron", 30), ("Grappling", 20), ("Wall", 10)]
    }

    var body: some View {
        let data = sportBreakdown.isEmpty ? fallbackData : sportBreakdown

        VStack(alignment: .leading, spacing: 12) {
            Text("TOP SPORTS")
                .font(.system(size: 10, weight: .semibold)).tracking(2.0)
                .foregroundStyle(.white.opacity(0.38))

            VStack(spacing: 8) {
                ForEach(data, id: \.sport) { entry in
                    HStack(spacing: 10) {
                        Text(entry.sport.capitalized)
                            .font(.system(size: 12, weight: .medium, design: .rounded)).foregroundStyle(.white)
                            .frame(width: 72, alignment: .leading)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.06)).frame(height: 8)
                                Capsule().fill(sportBarColor(for: entry.sport))
                                    .frame(width: geo.size.width * CGFloat(entry.count) / 100, height: 8)
                            }
                        }
                        .frame(height: 8)
                        Text("\(entry.count)%")
                            .font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(Color.kineticsSubtext)
                            .frame(width: 34, alignment: .trailing)
                    }
                }
            }
        }
        .padding(16)
        .background(Color.kineticsDark)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func sportBarColor(for sport: String) -> Color {
        switch sport.lowercased() {
        case "striking":                          return Color(hex: "#FF6B35")
        case "grappling":                         return Color(hex: "#5856D6")
        case "iron", "irontracker", "gym":        return Color(hex: "#FF9F0A")
        case "wall":                              return Color(hex: "#00BF96")
        default:                                  return Color.kineticsBlue
        }
    }
}
