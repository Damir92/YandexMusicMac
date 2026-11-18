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
public final class EqualizerParameterBridge: @unchecked Sendable {
    public static let shared = EqualizerParameterBridge()

    public struct Snapshot: Sendable {
        public let isEnabled: Bool
        public let preampDb: Float
        public let bandGains: [Float]
        public let generation: UInt64
    }

    private var lock = os_unfair_lock_s()
    private var isEnabled: Bool = false
    private var preampDb: Float = 0.0
    private var bandGains: [Float] = Array(repeating: 0.0, count: 10)
    private var generation: UInt64 = 1

    public init() {}

    public func update(isEnabled: Bool, preampDb: Float, bandGains: [Float]) {
        os_unfair_lock_lock(&lock)
        self.isEnabled = isEnabled
        self.preampDb = preampDb
        self.bandGains = bandGains
        self.generation &+= 1
        os_unfair_lock_unlock(&lock)
    }

    public func currentGeneration() -> UInt64 {
        os_unfair_lock_lock(&lock)
        let gen = self.generation
        os_unfair_lock_unlock(&lock)
        return gen
    }

    public func currentIsEnabled() -> Bool {
        os_unfair_lock_lock(&lock)
        let enabled = self.isEnabled
        os_unfair_lock_unlock(&lock)
        return enabled
    }

    public func readSnapshot() -> Snapshot {
        os_unfair_lock_lock(&lock)
        let snap = Snapshot(
            isEnabled: self.isEnabled,
            preampDb: self.preampDb,
            bandGains: self.bandGains,
            generation: self.generation
        )
        os_unfair_lock_unlock(&lock)
        return snap
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

    public var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: enabledKey)
            syncBridge()
        }
    }

    public var selectedPreset: YMEqualizerPreset {
        didSet {
            UserDefaults.standard.set(selectedPreset.rawValue, forKey: presetKey)
        }
    }

    public var bandGains: [Float] {
        didSet {
            UserDefaults.standard.set(bandGains, forKey: gainsKey)
            syncBridge()
        }
    }

    public var preampDb: Float {
        didSet {
            UserDefaults.standard.set(preampDb, forKey: preampKey)
            syncBridge()
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
