import SwiftUI

/// Today: tonight's sleep need and the bedtime that fits your usual wake time (Core/SleepPlanner.swift).
struct SleepPlanCard: View {
    let plan: SleepPlan

    var body: some View {
        Card {
            HStack(alignment: .firstTextBaseline) {
                SectionHeader(title: "Tonight")
                Spacer()
                Image(systemName: "moon.stars.fill").foregroundStyle(Theme.sleep)
            }
            HStack(alignment: .top) {
                stat("Need tonight", Format.duration(plan.needMin))
                Spacer()
                stat("In bed by", plan.bedtimeMin.map { Format.clock($0) } ?? "–")
                Spacer()
                stat("Wake at", plan.wakeMin.map { Format.clock($0) } ?? "–")
            }
            FlowLayout(spacing: 6) {
                part("Base \(Format.duration(plan.baseMin))")
                if plan.strainMin > 0 { part("+\(Format.duration(plan.strainMin)) for today's strain") }
                if plan.debtMin > 0 { part("+\(Format.duration(plan.debtMin)) to repay debt") }
                if plan.napMin > 0 { part("−\(Format.duration(plan.napMin)) naps") }
            }
            Text(explanation)
                .font(.caption)
                .foregroundStyle(Theme.tertiary)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sleep-plan")
    }

    private var explanation: String {
        let inBed = "\(Format.duration(plan.inBedMin)) in bed at your \(Int((plan.efficiency * 100).rounded()))% sleep efficiency"
        guard plan.bedtimeMin != nil, let basis = plan.wakeBasis else {
            return "\(inBed). A bedtime appears once 3 recent nights have a wake time."
        }
        let usual = basis == .all ? "your usual wake time" : "your usual \(basis.rawValue) wake time"
        return "\(inBed), to wake at \(usual). Today's strain and a quarter of the last week's sleep debt (up to 1h) add to your base need; today's naps take some off."
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(Theme.secondary)
            Text(value).font(Theme.number(22))
        }
    }

    private func part(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Theme.sleep.opacity(0.16)))
            .foregroundStyle(Theme.sleep)
    }
}
