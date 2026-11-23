import Foundation
import Observation
import os

/// Пресеты 10-полосного эквалайзера (32 Hz – 16 kHz, значения в дБ).
public enum YMEqualizerPreset: String, CaseIterable, Identifiable, Codable, Sendable {
    case flat = "flat"
    case rock = "rock"
    case pop = "pop"
    case electronic = "electronic"
    case bassBoost = "bassBoost"
    case vocal = "vocal"
    case classical = "classical"
    case jazz = "jazz"
    case custom = "custom"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .flat: return "По умолчанию"
        case .rock: return "Рок"
        case .pop: return "Поп"
        case .electronic: return "Электроника"
        case .bassBoost: return "Больше баса"
        case .vocal: return "Вокал"
        case .classical: return "Классика"
        case .jazz: return "Джаз"
        case .custom: return "Свой"
        }
    }

    /// 10 полос: 32, 64, 125, 250, 500, 1k, 2k, 4k, 8k, 16k Hz
    public var gains: [Float] {
        switch self {
        case .flat:       return [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
        case .rock:       return [4.5, 3.5, 1.5, -1.0, -1.5, 0.5, 2.5, 3.5, 4.5, 5.0]
        case .pop:        return [-1.5, 1.5, 3.5, 4.0, 2.0, -0.5, -1.5, 1.0, 2.5, 3.0]
        case .electronic: return [5.0, 4.0, 1.5, -1.0, -2.0, 0.5, 1.5, 3.0, 4.5, 5.0]
        case .bassBoost:  return [6.5, 5.5, 4.0, 2.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
        case .vocal:      return [-2.0, -1.5, 0.0, 2.5, 4.5, 4.5, 3.0, 1.0, -0.5, -1.0]
        case .classical:  return [3.5, 2.5, 1.0, 0.0, -0.5, 0.0, 1.5, 2.5, 3.5, 4.0]
        case .jazz:       return [3.0, 2.0, 1.0, 1.5, -1.0, -1.0, 0.5, 2.0, 3.0, 3.5]
        case .custom:     return [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
        }
    }
}

/// Потокобезопасный мост для чтения параметров эквалайзера из real-time потока CoreAudio без блокировки MainActor.
public final class EqualizerParameterBridge: Sendable {
    public static let shared = EqualizerParameterBridge()

    public struct RealtimeSnapshot: Sendable {
        public var isEnabled: Bool = false
        public var isFlatAndNeutral: Bool = true
        public var preampDb: Float = 0.0
        public var b0: Float = 0.0
        public var b1: Float = 0.0
        public var b2: Float = 0.0
        public var b3: Float = 0.0
        public var b4: Float = 0.0
        public var b5: Float = 0.0
        public var b6: Float = 0.0
        public var b7: Float = 0.0
        public var b8: Float = 0.0
        public var b9: Float = 0.0
        public var generation: UInt64 = 1

        public func bandGain(at index: Int) -> Float {
            switch index {
            case 0: return b0
            case 1: return b1
            case 2: return b2
            case 3: return b3
            case 4: return b4
            case 5: return b5
            case 6: return b6
            case 7: return b7
            case 8: return b8
            case 9: return b9
            default: return 0.0
            }
        }
    }

    public struct Snapshot: Sendable {
        public let isEnabled: Bool
        public let preampDb: Float
        public let bandGains: [Float]
        public let generation: UInt64
    }

    private let stateLock = OSAllocatedUnfairLock(initialState: RealtimeSnapshot())

    public init() {}

    public func update(isEnabled: Bool, preampDb: Float, bandGains: [Float]) {
        let g: (Int) -> Float = { idx in idx < bandGains.count ? bandGains[idx] : 0.0 }
        let b0 = g(0), b1 = g(1), b2 = g(2), b3 = g(3), b4 = g(4)
        let b5 = g(5), b6 = g(6), b7 = g(7), b8 = g(8), b9 = g(9)
        let flat = abs(preampDb) < 0.001
            && abs(b0) < 0.001 && abs(b1) < 0.001 && abs(b2) < 0.001 && abs(b3) < 0.001 && abs(b4) < 0.001
            && abs(b5) < 0.001 && abs(b6) < 0.001 && abs(b7) < 0.001 && abs(b8) < 0.001 && abs(b9) < 0.001

        stateLock.withLock { state in
            state.isEnabled = isEnabled
            state.isFlatAndNeutral = flat
            state.preampDb = preampDb
            state.b0 = b0; state.b1 = b1; state.b2 = b2; state.b3 = b3; state.b4 = b4
            state.b5 = b5; state.b6 = b6; state.b7 = b7; state.b8 = b8; state.b9 = b9
            state.generation &+= 1
        }
    }

    /// Non-blocking read for CoreAudio real-time thread (zero heap allocations, zero ARC).
    /// Returns nil only if main thread is mid-write; caller keeps using cached snapshot for this buffer.
    @inline(__always)
    public func tryReadRealtimeSnapshot() -> RealtimeSnapshot? {
        stateLock.withLockIfAvailable { $0 }
    }

    public func currentGeneration() -> UInt64 {
        stateLock.withLock { $0.generation }
    }

    public func currentIsEnabled() -> Bool {
        stateLock.withLock { $0.isEnabled }
    }

    public func isFlatAndNeutral() -> Bool {
        stateLock.withLock { $0.isFlatAndNeutral }
    }

    public func readSnapshot() -> Snapshot {
        let rt = stateLock.withLock { $0 }
        return Snapshot(
            isEnabled: rt.isEnabled,
            preampDb: rt.preampDb,
            bandGains: [rt.b0, rt.b1, rt.b2, rt.b3, rt.b4, rt.b5, rt.b6, rt.b7, rt.b8, rt.b9],
            generation: rt.generation
        )
    }
}

/// Наблюдаемое состояние эквалайзера для SwiftUI с сохранением настроек в UserDefaults.
@Observable
@MainActor
public final class EqualizerSettings {
    public static let shared = EqualizerSettings()

    public nonisolated static let bandFrequencies: [Float] = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
    public nonisolated static let bandLabels: [String] = ["32", "64", "125", "250", "500", "1K", "2K", "4K", "8K", "16K"]
    public nonisolated static let minGainDb: Float = -12.0
    public nonisolated static let maxGainDb: Float = 12.0

    private let enabledKey = "ym_eq_enabled"
    private let presetKey = "ym_eq_preset"
    private let gainsKey = "ym_eq_band_gains"
    private let preampKey = "ym_eq_preamp_db"

    @ObservationIgnored
    private var persistTask: Task<Void, Never>?

    public var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: enabledKey)
            syncBridge()
            NotificationCenter.default.post(name: .ymEqualizerEnabledDidChange, object: nil)
        }
    }

    public var selectedPreset: YMEqualizerPreset {
        didSet {
            UserDefaults.standard.set(selectedPreset.rawValue, forKey: presetKey)
        }
    }

    public var bandGains: [Float] {
        didSet {
            syncBridge()
            schedulePersistence()
        }
    }

    public var preampDb: Float {
        didSet {
            syncBridge()
            schedulePersistence()
        }
    }

    private func schedulePersistence() {
        persistTask?.cancel()
        persistTask = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            UserDefaults.standard.set(self.bandGains, forKey: self.gainsKey)
            UserDefaults.standard.set(self.preampDb, forKey: self.preampKey)
        }
    }

    public init() {
        let savedEnabled = UserDefaults.standard.bool(forKey: enabledKey)
        let savedPresetStr = UserDefaults.standard.string(forKey: presetKey)
        let resolvedPreset = savedPresetStr.flatMap(YMEqualizerPreset.init(rawValue:)) ?? .flat

        let savedGains = UserDefaults.standard.array(forKey: gainsKey) as? [Float]
            ?? (UserDefaults.standard.array(forKey: gainsKey) as? [Double])?.map { Float($0) }
        let resolvedGains: [Float]
        if let savedGains, savedGains.count == 10 {
            resolvedGains = savedGains.map { min(max($0, Self.minGainDb), Self.maxGainDb) }
        } else {
            resolvedGains = resolvedPreset.gains
        }

        let savedPreamp = UserDefaults.standard.object(forKey: preampKey) as? Float
            ?? Float(UserDefaults.standard.double(forKey: preampKey))
        let resolvedPreamp = min(max(savedPreamp, -6.0), 6.0)

        self.isEnabled = savedEnabled
        self.selectedPreset = resolvedPreset
        self.bandGains = resolvedGains
        self.preampDb = resolvedPreamp

        syncBridge()
    }

    public func selectPreset(_ preset: YMEqualizerPreset) {
        self.selectedPreset = preset
        if preset != .custom {
            self.bandGains = preset.gains
            if !isEnabled && preset != .flat {
                self.isEnabled = true
            }
        }
    }

    public func setBandGain(index: Int, gain: Float) {
        guard index >= 0 && index < bandGains.count else { return }
        let clamped = min(max(gain, Self.minGainDb), Self.maxGainDb)
        var updated = bandGains
        updated[index] = clamped
        self.bandGains = updated
        if selectedPreset != .custom {
            self.selectedPreset = .custom
        }
        if !isEnabled && abs(clamped) > 0.05 {
            self.isEnabled = true
        }
    }

    public func setPreamp(_ db: Float) {
        self.preampDb = min(max(db, -6.0), 6.0)
    }

    public func reset() {
        self.selectedPreset = .flat
        self.preampDb = 0.0
        self.bandGains = YMEqualizerPreset.flat.gains
    }

    private func syncBridge() {
        EqualizerParameterBridge.shared.update(
            isEnabled: isEnabled,
            preampDb: preampDb,
            bandGains: bandGains
        )
    }
}

extension Notification.Name {
    public static let ymEqualizerEnabledDidChange = Notification.Name("ymEqualizerEnabledDidChange")
}
