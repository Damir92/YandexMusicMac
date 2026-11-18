import Foundation
@preconcurrency import AVFoundation
import MediaToolbox
import AudioToolbox

/// Контекст экземпляра `MTAudioProcessingTap`, управляющий системным `AudioUnit` (`kAudioUnitSubType_NBandEQ`).
final class EqualizerTapContext {
    var audioUnit: AudioUnit?
    var sampleRate: Double = 44100.0
    var sampleCursor: Float64 = 0
    var lastAppliedGeneration: UInt64 = 0

    // Указатели, валидные только на время одного вызова `eqTapProcess`
    var activeTap: MTAudioProcessingTap?
    var activeFlagsOut: UnsafeMutablePointer<MTAudioProcessingTapFlags>?

    func setupAudioUnit(format: AudioStreamBasicDescription, maxFrames: CMItemCount) {
        disposeAudioUnit()

        var desc = AudioComponentDescription(
            componentType: kAudioUnitType_Effect,
            componentSubType: kAudioUnitSubType_NBandEQ,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )

        guard let component = AudioComponentFindNext(nil, &desc) else { return }

        var unit: AudioUnit?
        guard AudioComponentInstanceNew(component, &unit) == noErr, let au = unit else { return }

        var streamFormat = format
        let formatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)

        guard AudioUnitSetProperty(
            au,
            kAudioUnitProperty_StreamFormat,
            kAudioUnitScope_Input,
            0,
            &streamFormat,
            formatSize
        ) == noErr,
        AudioUnitSetProperty(
            au,
            kAudioUnitProperty_StreamFormat,
            kAudioUnitScope_Output,
            0,
            &streamFormat,
            formatSize
        ) == noErr else {
            AudioComponentInstanceDispose(au)
            return
        }

        var maxSlices = UInt32(maxFrames)
        AudioUnitSetProperty(
            au,
            kAudioUnitProperty_MaximumFramesPerSlice,
            kAudioUnitScope_Global,
            0,
            &maxSlices,
            UInt32(MemoryLayout<UInt32>.size)
        )

        // Настраиваем 10 частотных полос
        let freqs = EqualizerSettings.bandFrequencies
        var numBands = UInt32(freqs.count)
        AudioUnitSetProperty(
            au,
            kAUNBandEQProperty_NumberOfBands,
            kAudioUnitScope_Global,
            0,
            &numBands,
            UInt32(MemoryLayout<UInt32>.size)
        )

        // Подключаем входной render-callback, который читает PCM из MTAudioProcessingTap
        var renderCallback = AURenderCallbackStruct(
            inputProc: eqAudioUnitInputCallback,
            inputProcRefCon: Unmanaged.passUnretained(self).toOpaque()
        )
        AudioUnitSetProperty(
            au,
            kAudioUnitProperty_SetRenderCallback,
            kAudioUnitScope_Input,
            0,
            &renderCallback,
            UInt32(MemoryLayout<AURenderCallbackStruct>.size)
        )

        guard AudioUnitInitialize(au) == noErr else {
            AudioComponentInstanceDispose(au)
            return
        }

        for (index, freq) in freqs.enumerated() {
            let band = UInt32(index)
            let filterType: Float
            if index == 0 {
                filterType = Float(kAUNBandEQFilterType_ResonantLowShelf)
            } else if index == freqs.count - 1 {
                filterType = Float(kAUNBandEQFilterType_ResonantHighShelf)
            } else {
                filterType = Float(kAUNBandEQFilterType_Parametric)
            }

            AudioUnitSetParameter(au, kAUNBandEQParam_FilterType + band, kAudioUnitScope_Global, 0, filterType, 0)
            AudioUnitSetParameter(au, kAUNBandEQParam_Frequency + band, kAudioUnitScope_Global, 0, freq, 0)
            AudioUnitSetParameter(au, kAUNBandEQParam_Bandwidth + band, kAudioUnitScope_Global, 0, 1.0, 0)
            AudioUnitSetParameter(au, kAUNBandEQParam_BypassBand + band, kAudioUnitScope_Global, 0, 0.0, 0)
            AudioUnitSetParameter(au, kAUNBandEQParam_Gain + band, kAudioUnitScope_Global, 0, 0.0, 0)
        }

        self.sampleRate = format.mSampleRate > 0 ? format.mSampleRate : 44100.0
        self.sampleCursor = 0
        self.lastAppliedGeneration = 0
        self.audioUnit = au
    }

    func applyParametersIfNeeded() {
        guard let au = audioUnit else { return }
        let bridge = EqualizerParameterBridge.shared
        let gen = bridge.currentGeneration()
        guard gen != lastAppliedGeneration else { return }

        let snapshot = bridge.readSnapshot()
        AudioUnitSetParameter(au, kAUNBandEQParam_GlobalGain, kAudioUnitScope_Global, 0, snapshot.preampDb, 0)
        for index in 0..<min(snapshot.bandGains.count, 10) {
            AudioUnitSetParameter(
                au,
                kAUNBandEQParam_Gain + UInt32(index),
                kAudioUnitScope_Global,
                0,
                snapshot.bandGains[index],
                0
            )
        }
        self.lastAppliedGeneration = snapshot.generation
    }

    func disposeAudioUnit() {
        if let au = audioUnit {
            AudioUnitUninitialize(au)
            AudioComponentInstanceDispose(au)
            audioUnit = nil
        }
        activeTap = nil
        activeFlagsOut = nil
    }
}

// MARK: - CoreAudio / MediaToolbox C-Callbacks

private let eqAudioUnitInputCallback: AURenderCallback = { (
    inRefCon,
    _,
    _,
    _,
    inNumberFrames,
    ioData
) -> OSStatus in
    guard let ioData = ioData else { return noErr }
    let context = Unmanaged<EqualizerTapContext>.fromOpaque(inRefCon).takeUnretainedValue()
    guard let tap = context.activeTap, let flagsOut = context.activeFlagsOut else {
        return noErr
    }
    var sourceFrames: CMItemCount = 0
    return MTAudioProcessingTapGetSourceAudio(
        tap,
        CMItemCount(inNumberFrames),
        ioData,
        flagsOut,
        nil,
        &sourceFrames
    )
}

private let eqTapInit: MTAudioProcessingTapInitCallback = { (tap, clientInfo, tapStorageOut) in
    tapStorageOut.pointee = clientInfo
}

private let eqTapFinalize: MTAudioProcessingTapFinalizeCallback = { (tap) in
    let storage = MTAudioProcessingTapGetStorage(tap)
    let context = Unmanaged<EqualizerTapContext>.fromOpaque(storage).takeRetainedValue()
    context.disposeAudioUnit()
}

private let eqTapPrepare: MTAudioProcessingTapPrepareCallback = { (tap, maxFrames, processingFormat) in
    let storage = MTAudioProcessingTapGetStorage(tap)
    let context = Unmanaged<EqualizerTapContext>.fromOpaque(storage).takeUnretainedValue()
    context.setupAudioUnit(format: processingFormat.pointee, maxFrames: maxFrames)
}

private let eqTapUnprepare: MTAudioProcessingTapUnprepareCallback = { (tap) in
    let storage = MTAudioProcessingTapGetStorage(tap)
    let context = Unmanaged<EqualizerTapContext>.fromOpaque(storage).takeUnretainedValue()
    context.disposeAudioUnit()
}

private let eqTapProcess: MTAudioProcessingTapProcessCallback = { (
    tap,
    numberFrames,
    _,
    bufferListInOut,
    numberFramesOut,
    flagsOut
) in
    let storage = MTAudioProcessingTapGetStorage(tap)
    let context = Unmanaged<EqualizerTapContext>.fromOpaque(storage).takeUnretainedValue()

    // Если эквалайзер выключен, все полосы нейтральны или AudioUnit не инициализирован — прозрачный bypass без вызова AudioUnitRender
    guard EqualizerParameterBridge.shared.currentIsEnabled(),
          !EqualizerParameterBridge.shared.isFlatAndNeutral(),
          let au = context.audioUnit else {
        MTAudioProcessingTapGetSourceAudio(tap, numberFrames, bufferListInOut, flagsOut, nil, numberFramesOut)
        context.sampleCursor += Float64(numberFrames)
        return
    }

    context.applyParametersIfNeeded()
    context.activeTap = tap
    context.activeFlagsOut = flagsOut

    var actionFlags = AudioUnitRenderActionFlags(rawValue: 0)
    var timeStamp = AudioTimeStamp()
    timeStamp.mSampleTime = context.sampleCursor
    timeStamp.mFlags = .sampleTimeValid

    let status = AudioUnitRender(
        au,
        &actionFlags,
        &timeStamp,
        0,
        UInt32(numberFrames),
        bufferListInOut
    )

    context.activeTap = nil
    context.activeFlagsOut = nil

    if status == noErr {
        numberFramesOut.pointee = numberFrames
    } else {
        // Аварийный пропуск чистого аудио при сбое рендера AudioUnit
        MTAudioProcessingTapGetSourceAudio(tap, numberFrames, bufferListInOut, flagsOut, nil, numberFramesOut)
    }

    context.sampleCursor += Float64(numberFrames)
}

// MARK: - SDK-Agnostic MTAudioProcessingTapCreate Bridge

/// macOS 26/27 SDK signature (`UnsafeMutablePointer<MTAudioProcessingTap?>`)
@inline(__always)
private func invokeTapCreate(
    _ fn: (CFAllocator?, UnsafePointer<MTAudioProcessingTapCallbacks>, MTAudioProcessingTapCreationFlags, UnsafeMutablePointer<MTAudioProcessingTap?>) -> OSStatus,
    callbacks: inout MTAudioProcessingTapCallbacks
) -> (OSStatus, MTAudioProcessingTap?) {
    var tapOut: MTAudioProcessingTap?
    let status = fn(kCFAllocatorDefault, &callbacks, kMTAudioProcessingTapCreationFlag_PreEffects, &tapOut)
    return (status, tapOut)
}

/// macOS 14/15 SDK signature (`UnsafeMutablePointer<Unmanaged<MTAudioProcessingTap>?>`)
@inline(__always)
private func invokeTapCreate(
    _ fn: (CFAllocator?, UnsafePointer<MTAudioProcessingTapCallbacks>, MTAudioProcessingTapCreationFlags, UnsafeMutablePointer<Unmanaged<MTAudioProcessingTap>?>) -> OSStatus,
    callbacks: inout MTAudioProcessingTapCallbacks
) -> (OSStatus, MTAudioProcessingTap?) {
    var tapOut: Unmanaged<MTAudioProcessingTap>?
    let status = fn(kCFAllocatorDefault, &callbacks, kMTAudioProcessingTapCreationFlag_PreEffects, &tapOut)
    return (status, tapOut?.takeRetainedValue())
}

// MARK: - AVAudioMix Builder

public enum AudioEqualizerTapBuilder {
    /// Создаёт `AVAudioMix` с `MTAudioProcessingTap` для первой аудиодорожки `AVAsset`.
    @MainActor
    public static func makeAudioMix(for asset: AVAsset) async -> AVAudioMix? {
        do {
            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            guard let audioTrack = audioTracks.first else { return nil }

            let context = EqualizerTapContext()
            let retainedContext = Unmanaged.passRetained(context).toOpaque()

            var callbacks = MTAudioProcessingTapCallbacks(
                version: kMTAudioProcessingTapCallbacksVersion_0,
                clientInfo: retainedContext,
                init: eqTapInit,
                finalize: eqTapFinalize,
                prepare: eqTapPrepare,
                unprepare: eqTapUnprepare,
                process: eqTapProcess
            )

            let (status, tapOut) = invokeTapCreate(MTAudioProcessingTapCreate, callbacks: &callbacks)

            guard status == noErr, let tap = tapOut else {
                Unmanaged<EqualizerTapContext>.fromOpaque(retainedContext).release()
                return nil
            }

            let params = AVMutableAudioMixInputParameters(track: audioTrack)
            params.audioTapProcessor = tap

            let audioMix = AVMutableAudioMix()
            audioMix.inputParameters = [params]
            return audioMix
        } catch {
            return nil
        }
    }
}
