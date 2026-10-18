import CoreBluetooth
import Foundation

/// One Heart Rate Measurement (Bluetooth characteristic 0x2A37), decoded per the Bluetooth
/// SIG Heart Rate Profile. The Fitbit Air sends these when "Share heart rate" is on.
struct HeartRateMeasurement: Equatable {
    let bpm: Int
    /// Skin contact, or nil when the band doesn't report it.
    let contact: Bool?
    /// Beat-to-beat (RR) intervals in seconds; empty when the band doesn't send them.
    let rrIntervals: [Double]

    /// flags bit 0: the value is UInt16 (else UInt8); bits 1–2: contact detected / supported;
    /// bit 3: a UInt16 energy expended follows; bit 4: UInt16 RR intervals in 1/1024 s follow.
    static func parse(_ data: Data) -> HeartRateMeasurement? {
        let b = [UInt8](data)
        guard let flags = b.first else { return nil }
        var i = 1
        let bpm: Int
        if flags & 0x01 != 0 {
            guard b.count >= i + 2 else { return nil }
            bpm = Int(b[i]) | (Int(b[i + 1]) << 8)
            i += 2
        } else {
            guard b.count >= i + 1 else { return nil }
            bpm = Int(b[i])
            i += 1
        }
        if flags & 0x08 != 0 { i += 2 }
        var rr: [Double] = []
        if flags & 0x10 != 0 {
            while b.count >= i + 2 {
                rr.append(Double(Int(b[i]) | (Int(b[i + 1]) << 8)) / 1024)
                i += 2
            }
        }
        let contact: Bool? = flags & 0x04 != 0 ? flags & 0x02 != 0 : nil
        return HeartRateMeasurement(bpm: bpm, contact: contact, rrIntervals: rr)
    }
}

struct LiveHeartRateSample: Identifiable {
    let id: Int
    let date: Date
    let bpm: Int
}

/// A heart-rate sensor found while scanning.
struct LiveHeartRateDevice: Identifiable, Equatable {
    let id: UUID
    let name: String
}

private struct RRInterval {
    let date: Date
    let seconds: Double
}

/// Live heart rate straight from the band over Bluetooth, while FitStats is open (Google's API
/// only has heart rate after the band has synced). Everything runs on the main queue.
final class LiveHeartRateMonitor: NSObject, ObservableObject {
    enum State: Equatable {
        case idle, unsupported, poweredOff, unauthorized, scanning
        case connecting(String)
        case connected(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var devices: [LiveHeartRateDevice] = []
    @Published private(set) var samples: [LiveHeartRateSample] = []
    @Published private(set) var latest: HeartRateMeasurement?
    @Published private(set) var lastUpdate: Date?
    @Published private(set) var battery: Int?
    /// Whether the band has sent any beat-to-beat intervals this session.
    @Published private(set) var sendsRR = false
    /// RMSSD in ms over the last 60 s of beat-to-beat intervals (20 or more of them).
    @Published private(set) var liveRMSSD: Double?
    @Published private(set) var sessionMin: Int?
    @Published private(set) var sessionMax: Int?
    @Published private(set) var sessionAvg: Double?
    /// The Settings switch. Off: no Bluetooth at all, and Today hides the live card and button.
    @Published var enabled: Bool = UserDefaults.standard.object(forKey: LiveHeartRateMonitor.enabledKey) as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
            if !enabled {
                if active { end() }
            } else if users > 0 && !paused && !active {
                begin()
            }
        }
    }

    static let heartRateService = CBUUID(string: "180D")
    static let measurementCharacteristic = CBUUID(string: "2A37")
    static let batteryService = CBUUID(string: "180F")
    static let batteryCharacteristic = CBUUID(string: "2A19")
    private static let rememberedKey = "liveHR.peripheral"
    private static let enabledKey = "liveHR.enabled"
    private static let keepSeconds: TimeInterval = 600

    private let fixtureMode = !(ProcessInfo.processInfo.environment["FITSTATS_FIXTURES"] ?? "").isEmpty
    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var found: [UUID: CBPeripheral] = [:]
    private var rr: [RRInterval] = []
    private var nextId = 0
    private var sessionSum = 0
    private var sessionCount = 0
    /// Screens and cards showing live heart rate; Bluetooth runs while there is at least one.
    private var users = 0
    private var paused = false
    /// Whether Bluetooth (or the fixture stream) is running.
    private var active = false
    /// The pending let-go after the last user left: moving from the Home card to the full
    /// screen briefly has no user, and keeping the connection keeps the session's readings.
    private var endWork: DispatchWorkItem?
    private var fixtureTimer: Timer?

    private var remembered: UUID? {
        get { UserDefaults.standard.string(forKey: Self.rememberedKey).flatMap(UUID.init(uuidString:)) }
        set { UserDefaults.standard.set(newValue?.uuidString, forKey: Self.rememberedKey) }
    }

    func start() {
        users += 1
        endWork?.cancel()
        endWork = nil
        if enabled && !active && !paused { begin() }
    }

    func stop() {
        users = Swift.max(0, users - 1)
        guard users == 0 else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.users == 0 else { return }
            self.end()
        }
        endWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
    }

    /// The app went to the background: let go of the band until it comes back.
    func pause() {
        guard !paused else { return }
        paused = true
        if active { end() }
    }

    func resume() {
        guard paused else { return }
        paused = false
        if enabled && users > 0 && !active { begin() }
    }

    /// Connect to a device the user picked from the list.
    func connect(_ device: LiveHeartRateDevice) {
        guard let p = found[device.id] else { return }
        remembered = device.id
        connect(p)
    }

    // MARK: lifecycle

    private func begin() {
        active = true
        resetSession()
        if fixtureMode {
            startFixture()
            return
        }
        if let central {
            centralManagerDidUpdateState(central)
        } else {
            // Created only now, so iOS asks for Bluetooth permission when live heart rate is opened.
            central = CBCentralManager(delegate: self, queue: .main)
        }
    }

    private func end() {
        active = false
        endWork?.cancel()
        endWork = nil
        fixtureTimer?.invalidate()
        fixtureTimer = nil
        if let central {
            if central.isScanning { central.stopScan() }
            if let peripheral { central.cancelPeripheralConnection(peripheral) }
        }
        peripheral = nil
        if state != .unsupported && state != .unauthorized && state != .poweredOff { state = .idle }
    }

    private func resetSession() {
        samples = []
        rr = []
        latest = nil
        lastUpdate = nil
        liveRMSSD = nil
        sendsRR = false
        sessionMin = nil
        sessionMax = nil
        sessionAvg = nil
        sessionSum = 0
        sessionCount = 0
    }

    private func scan() {
        guard let central, users > 0, !paused else { return }
        // The band may already be connected to this iPhone (by the Google Health app) and then
        // not advertise; iOS still hands it over when it exposes the heart-rate service.
        let connected = central.retrieveConnectedPeripherals(withServices: [Self.heartRateService])
        if let p = connected.first(where: { $0.identifier == remembered }) ?? connected.first(where: { ($0.name ?? "").contains("Fitbit") }) {
            connect(p)
            return
        }
        state = .scanning
        central.scanForPeripherals(withServices: [Self.heartRateService], options: nil)
    }

    private func connect(_ p: CBPeripheral) {
        guard let central else { return }
        if central.isScanning { central.stopScan() }
        if let current = peripheral, current.identifier != p.identifier { central.cancelPeripheralConnection(current) }
        peripheral = p
        p.delegate = self
        state = .connecting(p.name ?? "Heart-rate sensor")
        central.connect(p, options: nil)
    }

    // MARK: readings

    private func record(_ m: HeartRateMeasurement, at now: Date = Date()) {
        latest = m
        lastUpdate = now
        guard m.bpm > 0, m.contact != false else { return }
        nextId += 1
        samples.append(LiveHeartRateSample(id: nextId, date: now, bpm: m.bpm))
        samples.removeAll { now.timeIntervalSince($0.date) > Self.keepSeconds }
        sessionCount += 1
        sessionSum += m.bpm
        sessionMin = Swift.min(sessionMin ?? m.bpm, m.bpm)
        sessionMax = Swift.max(sessionMax ?? m.bpm, m.bpm)
        sessionAvg = Double(sessionSum) / Double(sessionCount)
        if !m.rrIntervals.isEmpty {
            sendsRR = true
            rr.append(contentsOf: m.rrIntervals.map { RRInterval(date: now, seconds: $0) })
            rr.removeAll { now.timeIntervalSince($0.date) > 120 }
            liveRMSSD = Self.rmssd(rr.filter { now.timeIntervalSince($0.date) <= 60 }.map(\.seconds))
        }
    }

    /// RMSSD in ms. Intervals outside 0.3–2 s and jumps over 20 % between neighbours are
    /// artifacts (a missed or extra beat) and are left out; nil under 20 intervals.
    static func rmssd(_ intervals: [Double]) -> Double? {
        let clean = intervals.filter { $0 >= 0.3 && $0 <= 2.0 }
        guard clean.count >= 20 else { return nil }
        var squares: [Double] = []
        for k in 1..<clean.count {
            let a = clean[k - 1], b = clean[k]
            if abs(b - a) <= 0.2 * a { squares.append(((b - a) * 1000) * ((b - a) * 1000)) }
        }
        guard squares.count >= 10 else { return nil }
        return (squares.reduce(0, +) / Double(squares.count)).squareRoot()
    }

    // MARK: fixture mode (CI screenshots: no Bluetooth in the simulator)

    private func startFixture() {
        state = .connected("Fitbit Air")
        battery = 81
        let now = Date()
        for s in stride(from: 300, through: 1, by: -1) { record(fixtureReading(Double(s)), at: now.addingTimeInterval(-Double(s))) }
        fixtureTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.record(self.fixtureReading(0))
        }
    }

    private func fixtureReading(_ secondsAgo: Double) -> HeartRateMeasurement {
        let t = Date().timeIntervalSince1970 - secondsAgo
        let bpm = Int((74 + 5 * sin(t / 23) + 2 * sin(t / 3.7)).rounded())
        let beat = 60 / Double(bpm)
        return HeartRateMeasurement(bpm: bpm, contact: true, rrIntervals: [beat * (1 + 0.03 * sin(t)), beat * (1 - 0.03 * sin(t / 1.3))])
    }
}

extension LiveHeartRateMonitor: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            if users > 0 && !paused && peripheral == nil { scan() }
        case .poweredOff:
            state = .poweredOff
        case .unauthorized:
            state = .unauthorized
        case .unsupported:
            state = .unsupported
        default:
            break
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = peripheral.name ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? "Heart-rate sensor"
        found[peripheral.identifier] = peripheral
        if !devices.contains(where: { $0.id == peripheral.identifier }) {
            devices.append(LiveHeartRateDevice(id: peripheral.identifier, name: name))
        }
        guard self.peripheral == nil else { return }
        if peripheral.identifier == remembered || (remembered == nil && name.contains("Fitbit")) {
            connect(peripheral)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        remembered = peripheral.identifier
        state = .connected(peripheral.name ?? "Heart-rate sensor")
        peripheral.discoverServices([Self.heartRateService, Self.batteryService])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        // Look for it again by scanning only, so a band that keeps failing isn't retried in a tight loop.
        self.peripheral = nil
        guard users > 0, !paused else { return }
        state = .scanning
        central.scanForPeripherals(withServices: [Self.heartRateService], options: nil)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard users > 0, !paused, self.peripheral?.identifier == peripheral.identifier else { return }
        // Out of range or sharing switched off: a pending connect completes when it is back.
        state = .connecting(peripheral.name ?? "Heart-rate sensor")
        central.connect(peripheral, options: nil)
    }
}

extension LiveHeartRateMonitor: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        for service in peripheral.services ?? [] {
            if service.uuid == Self.heartRateService {
                peripheral.discoverCharacteristics([Self.measurementCharacteristic], for: service)
            } else if service.uuid == Self.batteryService {
                peripheral.discoverCharacteristics([Self.batteryCharacteristic], for: service)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for c in service.characteristics ?? [] {
            if c.uuid == Self.measurementCharacteristic {
                peripheral.setNotifyValue(true, for: c)
            } else if c.uuid == Self.batteryCharacteristic {
                peripheral.readValue(for: c)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let data = characteristic.value else { return }
        if characteristic.uuid == Self.measurementCharacteristic {
            if let m = HeartRateMeasurement.parse(data) { record(m) }
        } else if characteristic.uuid == Self.batteryCharacteristic, let level = data.first {
            battery = Int(level)
        }
    }
}
