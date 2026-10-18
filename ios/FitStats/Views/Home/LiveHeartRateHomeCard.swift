import SwiftUI

/// Home: live heart rate from the band over Bluetooth, started from the card (Bluetooth runs
/// only while it is started and the card is on screen).
struct LiveHeartRateHomeCard: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var live: LiveHeartRateMonitor
    @State private var running = false

    var body: some View {
        Card {
            HStack(alignment: .firstTextBaseline) {
                SectionHeader(title: "Live heart rate", subtitle: "From your Fitbit Air over Bluetooth")
                Spacer()
                NavigationLink(value: DetailRoute.liveHeartRate) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right").font(.caption)
                }
                .accessibilityLabel("Open live heart rate")
            }
            if running {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(Theme.heart)
                        .symbolEffect(.bounce, value: live.samples.last?.id ?? 0)
                    Text(bpmText).font(Theme.number(40))
                    Text("bpm").foregroundStyle(Theme.secondary)
                    Spacer()
                    Button("Stop") { toggle() }
                        .font(.subheadline.weight(.semibold))
                }
                Text(caption).font(.caption).foregroundStyle(Theme.tertiary)
            } else {
                Button {
                    toggle()
                } label: {
                    Label("Start", systemImage: "dot.radiowaves.left.and.right")
                        .font(.subheadline.weight(.semibold))
                }
                Text("Turn on Share heart rate for your Fitbit Air in the Google Health app first.")
                    .font(.caption)
                    .foregroundStyle(Theme.tertiary)
            }
        }
        .onDisappear {
            if running {
                live.stop()
                running = false
            }
        }
    }

    private var isLive: Bool {
        guard case .connected = live.state, let at = live.lastUpdate else { return false }
        return Date().timeIntervalSince(at) < 10 && live.latest?.contact != false
    }

    private var bpmText: String {
        guard isLive, let bpm = live.latest?.bpm, bpm > 0 else { return "–" }
        return "\(bpm)"
    }

    private var caption: String {
        if isLive, let bpm = live.latest?.bpm {
            return LiveZone(bpm: bpm, rhr: model.liveRestingHr, maxHr: model.liveMaxHr).name
        }
        switch live.state {
        case .connected: return "Waiting for a reading…"
        case .connecting(let name): return "Connecting to \(name)…"
        case .scanning: return "Looking for your Fitbit Air…"
        case .poweredOff: return "Turn on Bluetooth."
        case .unauthorized: return "Allow Bluetooth for FitStats in Settings."
        case .unsupported: return "Bluetooth isn't available."
        case .idle: return "Starting…"
        }
    }

    private func toggle() {
        if running { live.stop() } else { live.start() }
        running.toggle()
    }
}
