import Foundation
import AVFoundation
import CoreAudio
import AudioToolbox
import AppKit

// MARK: - Audio Device Model

struct AudioDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let name: String
    let isInput: Bool
    let isOutput: Bool
}

// MARK: - Voice Mode Presets (Core Vocal Suite)

enum VoiceMode: String, CaseIterable, Identifiable {
    case normal = "Normal (Off)"
    case karaoke = "🎤 Karaoke (Pop)"
    case studio = "🎙️ Studio Pro"
    case warmAcoustic = "🎸 Warm Acoustic"
    case concert = "🏛️ Concert Arena"

    var id: String { rawValue }
}

enum ReverbPresetOption: String, CaseIterable, Identifiable {
    case karaokeHall = "Karaoke Hall"
    case studioRoom = "Studio Room"
    case concertArena = "Concert Arena"

    var id: String { rawValue }

    var avPreset: AVAudioUnitReverbPreset {
        switch self {
        case .karaokeHall: return .mediumHall
        case .studioRoom: return .largeRoom
        case .concertArena: return .cathedral
        }
    }
}

// MARK: - Studio Vocal Compressor (Auto Leveling)

enum CompressorProfile: String, CaseIterable, Identifiable {
    case gentle = "🎙️ Gentle Vocal (Natural)"
    case broadcast = "📻 Broadcast Punch"
    case aggressive = "🛡️ Heavy Leveler"

    var id: String { rawValue }
}

// MARK: - Creative Sound FX Modes

enum CreativeVoiceMode: String, CaseIterable, Identifiable {
    case off = "Normal (Off)"
    case walkieTalkie = "📻 Walkie-Talkie"
    case megaphone = "📢 Megaphone"
    case vintagePhone = "📞 Telephone"
    case alien = "🛸 Sci-Fi Alien"

    var id: String { rawValue }
}

// MARK: - Voice Check State

enum VoiceCheckState: Equatable {
    case idle
    case recording(secondsRemaining: Int)
    case playing(secondsRemaining: Int)
}

/// Manages the ultra-low-latency direct audio engine with studio vocal enhancements,
/// dynamic compressor auto-leveler, creative voice effects, smart noise gate, and 5s voice check.
final class AudioEngineManager: ObservableObject {
    // MARK: - Published UI State (Core & Devices)
    @Published var isRunning = false
    @Published var availableInputDevices: [AudioDevice] = []
    @Published var availableOutputDevices: [AudioDevice] = []
    @Published var selectedInputDeviceID: AudioDeviceID = 0
    @Published var selectedOutputDeviceID: AudioDeviceID = 0
    @Published var isBluetoothInputWarning = false

    // MARK: - Published Audio Controls
    @Published var gain: Double = 1.0 // 1.0 = 100%, range 0.0 - 2.0 (0% - 200%)
    @Published var isMuted: Bool = false
    @Published var bufferSize: UInt32 = 64 // default to low latency 64 frames
    @Published var audioLevel: Float = 0.0
    @Published var errorMessage: String?

    // MARK: - Published Smart Noise Gate
    @Published var isNoiseGateEnabled: Bool = true
    @Published var noiseGateSensitivity: Double = 35.0 // 0% to 100%
    @Published var isGateOpen: Bool = true

    // MARK: - Published Studio Vocal Enhancer (Core Suite)
    @Published var voiceMode: VoiceMode = .normal
    @Published var vocalClarity: Double = 0.0 // 0.0 to 100.0 (Presence & Air Shine)
    @Published var reverbMix: Double = 0.0 // 0.0 to 100.0 (0% = Dry, 100% = Wet)
    @Published var reverbPreset: ReverbPresetOption = .karaokeHall
    @Published var echoMix: Double = 0.0 // 0.0 to 50.0 (0% = Off, 50% = Max Echo)

    // Custom 3-Band Tone Adjustments
    @Published var bassGain: Double = 0.0 // -6.0 to +6.0 dB
    @Published var midGain: Double = 0.0 // -6.0 to +6.0 dB
    @Published var trebleGain: Double = 0.0 // -6.0 to +6.0 dB

    // MARK: - Published Studio Vocal Compressor
    @Published var isCompressorEnabled: Bool = false
    @Published var compressorProfile: CompressorProfile = .gentle

    // MARK: - Published Creative Sound FX
    @Published var creativeVoiceMode: CreativeVoiceMode = .off

    // 5-Second Voice Check Preview
    @Published var voiceCheckState: VoiceCheckState = .idle

    // MARK: - Internal Audio Nodes & Graph
    private let engine = AVAudioEngine()
    private let gainMixer = AVAudioMixerNode()

    // Apple Native Studio Dynamics Processor (Compressor)
    private let compNode: AVAudioUnitEffect = {
        var compDesc = AudioComponentDescription(
            componentType: kAudioUnitType_Effect,
            componentSubType: kAudioUnitSubType_DynamicsProcessor,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        return AVAudioUnitEffect(audioComponentDescription: compDesc)
    }()

    // Apple Native Distortion / Creative FX Node
    private let distortionNode = AVAudioUnitDistortion()

    // 5-Band Parametric EQ, Delay, Reverb, Player
    private let eqNode = AVAudioUnitEQ(numberOfBands: 5)
    private let delayNode = AVAudioUnitDelay()
    private let reverbNode = AVAudioUnitReverb()
    private let playerNode = AVAudioPlayerNode()

    private var isTapInstalled = false
    private var currentGateGain: Float = 1.0
    private var isVoiceCheckRecording = false
    private var recordedVoiceSamples: [Float] = []
    private var voiceCheckTimer: Timer?
    private var currentSampleRate: Double = 48000.0

    // Event & Notification Observers
    private var hardwareListenerRegistered = false
    private var configChangeObserver: NSObjectProtocol?
    private var localKeyMonitor: Any?
    private var globalKeyMonitor: Any?

    init() {
        // STEP 1: Attach audio nodes to engine graph
        engine.attach(gainMixer)
        engine.attach(compNode)
        engine.attach(distortionNode)
        engine.attach(eqNode)
        engine.attach(delayNode)
        engine.attach(reverbNode)
        engine.attach(playerNode)

        // Configure default parametric EQ bands
        configureEQDefaults()

        // Configure initial effect parameters
        configureEffectDefaults()

        // Configure initial Compressor & Creative parameters
        applyCompressorParameters()
        applyCreativeVoiceParameters()

        // STEP 2: Configure default hardware buffer size early so hardware settles
        applyHardwareBufferSize(bufferSize)

        // STEP 3: Query initial macOS audio devices and set default selection
        refreshDevices()

        // STEP 4: Listen for system hardware audio device changes
        registerHardwareListeners()

        // STEP 5: Listen for audio engine configuration changes
        registerConfigurationChangeListener()

        // STEP 6: Register Mute Hotkeys (⌥ Option + M and Space)
        setupHotkeys()
    }

    deinit {
        stop()
        voiceCheckTimer?.invalidate()
        unregisterHardwareListeners()
        if let observer = configChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let monitor = localKeyMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = globalKeyMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    // MARK: - Parametric EQ Configuration

    private func configureEQDefaults() {
        // Band 0: High-Pass Filter (Low-Cut @ 80Hz) to remove desk thumps & mic breath rumble
        let band0 = eqNode.bands[0]
        band0.filterType = .highPass
        band0.frequency = 80.0
        band0.bypass = false

        // Band 1: Vocal Warmth (Low Shelf @ 220Hz)
        let band1 = eqNode.bands[1]
        band1.filterType = .lowShelf
        band1.frequency = 220.0
        band1.gain = 0.0
        band1.bypass = false

        // Band 2: De-Mud & Mid Control (Parametric @ 500Hz)
        let band2 = eqNode.bands[2]
        band2.filterType = .parametric
        band2.frequency = 500.0
        band2.bandwidth = 1.0
        band2.gain = 0.0
        band2.bypass = false

        // Band 3: Vocal Presence & Treble (Parametric @ 3500Hz)
        let band3 = eqNode.bands[3]
        band3.filterType = .parametric
        band3.frequency = 3500.0
        band3.bandwidth = 1.0
        band3.gain = 0.0
        band3.bypass = false

        // Band 4: Vocal Air Sparkle (High Shelf @ 10,000Hz)
        let band4 = eqNode.bands[4]
        band4.filterType = .highShelf
        band4.frequency = 10000.0
        band4.gain = 0.0
        band4.bypass = false
    }

    // MARK: - Device Detection & Monitoring

    /// Refreshes all available macOS input and output devices.
    func refreshDevices() {
        let allDevices = Self.queryAllDevices()
        let inDevs = allDevices.filter { $0.isInput }
        let outDevs = allDevices.filter { $0.isOutput }

        DispatchQueue.main.async {
            self.availableInputDevices = inDevs
            self.availableOutputDevices = outDevs

            if self.selectedInputDeviceID == 0 || !inDevs.contains(where: { $0.id == self.selectedInputDeviceID }) {
                self.selectedInputDeviceID = self.getDefaultDeviceID(isInput: true)
            }
            if self.selectedOutputDeviceID == 0 || !outDevs.contains(where: { $0.id == self.selectedOutputDeviceID }) {
                self.selectedOutputDeviceID = self.getDefaultDeviceID(isInput: false)
            }
            self.checkBluetoothInput()
        }
    }

    /// Selects an input device and reapplies if engine is running.
    func selectInputDevice(id: AudioDeviceID) {
        selectedInputDeviceID = id
        checkBluetoothInput()
        applyDeviceSelectionToHardware(inputID: id, outputID: selectedOutputDeviceID)

        if isRunning {
            stop()
            start()
        }
    }

    /// Selects an output device and reapplies if engine is running.
    func selectOutputDevice(id: AudioDeviceID) {
        selectedOutputDeviceID = id
        applyDeviceSelectionToHardware(inputID: selectedInputDeviceID, outputID: id)

        if isRunning {
            stop()
            start()
        }
    }

    private func checkBluetoothInput() {
        if let dev = availableInputDevices.first(where: { $0.id == selectedInputDeviceID }) {
            let lower = dev.name.lowercased()
            isBluetoothInputWarning = lower.contains("airpod") || lower.contains("bluetooth") || lower.contains("buds") || lower.contains("wireless")
        } else {
            isBluetoothInputWarning = false
        }
    }

    private func applyDeviceSelectionToHardware(inputID: AudioDeviceID, outputID: AudioDeviceID) {
        if inputID != 0 {
            var inID = inputID
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultInputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            _ = AudioObjectSetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                0,
                nil,
                UInt32(MemoryLayout<AudioDeviceID>.size),
                &inID
            )
        }

        if outputID != 0 {
            var outID = outputID
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            _ = AudioObjectSetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                0,
                nil,
                UInt32(MemoryLayout<AudioDeviceID>.size),
                &outID
            )
        }
    }

    // MARK: - Microphone Permission Verification

    private func checkMicrophonePermission(completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async { completion(granted) }
            }
        case .denied, .restricted:
            completion(false)
        @unknown default:
            completion(false)
        }
    }

    // MARK: - Audio Engine Lifecycle

    /// Starts live microphone passthrough with low-latency direct hardware streaming.
    func start() {
        guard !isRunning else { return }
        errorMessage = nil

        checkMicrophonePermission { [weak self] granted in
            guard let self = self else { return }
            guard granted else {
                self.errorMessage = "Microphone access is required. Please grant permission in System Settings > Privacy & Security > Microphone."
                return
            }

            self.startEngine()
        }
    }

    private func startEngine() {
        refreshDevices()

        let inputNode = engine.inputNode

        // STEP 1: Disconnect any previous connections
        engine.disconnectNodeOutput(inputNode)
        engine.disconnectNodeInput(gainMixer)
        engine.disconnectNodeOutput(gainMixer)
        engine.disconnectNodeInput(compNode)
        engine.disconnectNodeOutput(compNode)
        engine.disconnectNodeInput(distortionNode)
        engine.disconnectNodeOutput(distortionNode)
        engine.disconnectNodeInput(eqNode)
        engine.disconnectNodeOutput(eqNode)
        engine.disconnectNodeInput(delayNode)
        engine.disconnectNodeOutput(delayNode)
        engine.disconnectNodeInput(reverbNode)
        engine.disconnectNodeOutput(reverbNode)
        engine.disconnectNodeOutput(playerNode)

        // STEP 2: Retrieve valid inputFormat from inputNode
        var inputFormat = inputNode.outputFormat(forBus: 0)

        if inputFormat.sampleRate == 0 || inputFormat.channelCount == 0 {
            engine.reset()
            inputFormat = inputNode.outputFormat(forBus: 0)
        }

        guard inputFormat.sampleRate > 0 && inputFormat.channelCount > 0 else {
            errorMessage = "No microphone input detected. Please verify microphone in System Settings > Sound."
            return
        }

        currentSampleRate = inputFormat.sampleRate
        let outputFormat = AVAudioFormat(standardFormatWithSampleRate: currentSampleRate, channels: 2)!

        // STEP 3: Connect direct native audio chain:
        // inputNode -> gainMixer -> compNode -> distortionNode -> eqNode -> delayNode -> reverbNode -> mainMixerNode -> outputNode
        engine.connect(inputNode, to: gainMixer, format: inputFormat)
        engine.connect(gainMixer, to: compNode, format: nil)
        engine.connect(compNode, to: distortionNode, format: nil)
        engine.connect(distortionNode, to: eqNode, format: nil)
        engine.connect(eqNode, to: delayNode, format: nil)
        engine.connect(delayNode, to: reverbNode, format: nil)
        engine.connect(reverbNode, to: engine.mainMixerNode, format: nil)

        // Connect playerNode for 5s voice check playback preview
        engine.connect(playerNode, to: engine.mainMixerNode, format: outputFormat)

        // Apply initial volume & mute state
        gainMixer.outputVolume = isMuted ? 0.0 : Float(gain)

        // Update effect node settings
        updateEffects()
        applyCompressorParameters()
        applyCreativeVoiceParameters()

        // STEP 4: Install smart audio tap for Noise Gate, Metering, and Voice Check Recording
        installAudioMeterTap(on: inputNode, format: inputFormat)

        // STEP 5: Prepare and start audio engine
        do {
            engine.prepare()
            try engine.start()
            isRunning = true
        } catch {
            errorMessage = "Failed to start audio engine: \(error.localizedDescription)"
            stop()
        }
    }

    /// Stops live microphone passthrough and frees resources.
    func stop() {
        removeAudioMeterTap()
        cancelVoiceCheck()
        engine.stop()
        engine.disconnectNodeOutput(engine.inputNode)
        engine.disconnectNodeInput(gainMixer)
        engine.disconnectNodeOutput(gainMixer)
        engine.disconnectNodeInput(compNode)
        engine.disconnectNodeOutput(compNode)
        engine.disconnectNodeInput(distortionNode)
        engine.disconnectNodeOutput(distortionNode)
        engine.disconnectNodeInput(eqNode)
        engine.disconnectNodeOutput(eqNode)
        engine.disconnectNodeInput(delayNode)
        engine.disconnectNodeOutput(delayNode)
        engine.disconnectNodeInput(reverbNode)
        engine.disconnectNodeOutput(reverbNode)
        engine.disconnectNodeOutput(playerNode)
        engine.reset()
        isRunning = false
        audioLevel = 0.0
    }

    // MARK: - Gain & Mute Controls

    /// Updates the volume gain multiplier (0.0 to 2.0 = 0% to 200%).
    func updateGain(_ newGain: Double) {
        gain = newGain
        applyEffectiveGain()
    }

    /// Toggles the Mute state instantly.
    func toggleMute() {
        isMuted.toggle()
        applyEffectiveGain()
    }

    private func applyEffectiveGain() {
        guard !isMuted else {
            gainMixer.outputVolume = 0.0
            return
        }
        // Multiply by Smart Noise Gate gain envelope
        gainMixer.outputVolume = Float(gain) * currentGateGain
    }

    // MARK: - Smart Noise Gate & Protection

    func updateNoiseGate(enabled: Bool, sensitivity: Double) {
        isNoiseGateEnabled = enabled
        noiseGateSensitivity = sensitivity
        if !enabled {
            currentGateGain = 1.0
            isGateOpen = true
            applyEffectiveGain()
        }
    }

    // MARK: - Studio Vocal Compressor (Auto Leveling)

    func updateCompressor(enabled: Bool, profile: CompressorProfile) {
        isCompressorEnabled = enabled
        compressorProfile = profile
        applyCompressorParameters()
    }

    private func applyCompressorParameters() {
        let au = compNode.audioUnit
        compNode.bypass = !isCompressorEnabled
        guard isCompressorEnabled else { return }

        switch compressorProfile {
        case .gentle:
            // Natural vocal compression: catches peaks gently, lifts quiet notes
            AudioUnitSetParameter(au, kDynamicsProcessorParam_Threshold, kAudioUnitScope_Global, 0, -18.0, 0)
            AudioUnitSetParameter(au, kDynamicsProcessorParam_HeadRoom, kAudioUnitScope_Global, 0, 5.0, 0)
            AudioUnitSetParameter(au, kDynamicsProcessorParam_AttackTime, kAudioUnitScope_Global, 0, 0.005, 0)
            AudioUnitSetParameter(au, kDynamicsProcessorParam_ReleaseTime, kAudioUnitScope_Global, 0, 0.080, 0)
            AudioUnitSetParameter(au, kDynamicsProcessorParam_OverallGain, kAudioUnitScope_Global, 0, 3.0, 0)

        case .broadcast:
            // Radio broadcast punch: tight dynamics, crisp consistency
            AudioUnitSetParameter(au, kDynamicsProcessorParam_Threshold, kAudioUnitScope_Global, 0, -24.0, 0)
            AudioUnitSetParameter(au, kDynamicsProcessorParam_HeadRoom, kAudioUnitScope_Global, 0, 3.0, 0)
            AudioUnitSetParameter(au, kDynamicsProcessorParam_AttackTime, kAudioUnitScope_Global, 0, 0.002, 0)
            AudioUnitSetParameter(au, kDynamicsProcessorParam_ReleaseTime, kAudioUnitScope_Global, 0, 0.050, 0)
            AudioUnitSetParameter(au, kDynamicsProcessorParam_OverallGain, kAudioUnitScope_Global, 0, 5.0, 0)

        case .aggressive:
            // Heavy vocal leveler: whisper is as audible as normal speech, yells are clamped
            AudioUnitSetParameter(au, kDynamicsProcessorParam_Threshold, kAudioUnitScope_Global, 0, -30.0, 0)
            AudioUnitSetParameter(au, kDynamicsProcessorParam_HeadRoom, kAudioUnitScope_Global, 0, 2.0, 0)
            AudioUnitSetParameter(au, kDynamicsProcessorParam_AttackTime, kAudioUnitScope_Global, 0, 0.001, 0)
            AudioUnitSetParameter(au, kDynamicsProcessorParam_ReleaseTime, kAudioUnitScope_Global, 0, 0.040, 0)
            AudioUnitSetParameter(au, kDynamicsProcessorParam_OverallGain, kAudioUnitScope_Global, 0, 7.0, 0)
        }
    }

    // MARK: - Creative Sound FX Modes

    func setCreativeVoiceMode(_ mode: CreativeVoiceMode) {
        creativeVoiceMode = mode
        applyCreativeVoiceParameters()
    }

    private func applyCreativeVoiceParameters() {
        switch creativeVoiceMode {
        case .off:
            distortionNode.bypass = true
            distortionNode.wetDryMix = 0.0
            updateEQParameters()

        case .walkieTalkie:
            distortionNode.bypass = false
            distortionNode.loadFactoryPreset(.speechRadioTower)
            distortionNode.preGain = -2.0
            distortionNode.wetDryMix = 65.0
            updateEQParameters()

        case .megaphone:
            distortionNode.bypass = false
            distortionNode.loadFactoryPreset(.multiBrokenSpeaker)
            distortionNode.preGain = 2.0
            distortionNode.wetDryMix = 50.0
            updateEQParameters()

        case .vintagePhone:
            distortionNode.bypass = false
            distortionNode.loadFactoryPreset(.multiCellphoneConcert)
            distortionNode.preGain = 0.0
            distortionNode.wetDryMix = 60.0
            updateEQParameters()

        case .alien:
            distortionNode.bypass = false
            distortionNode.loadFactoryPreset(.speechCosmicInterference)
            distortionNode.preGain = -1.0
            distortionNode.wetDryMix = 70.0
            updateEQParameters()
        }
    }

    // MARK: - 5-Second Voice Check Preview

    /// Records 5 seconds of the user's voice and plays it back immediately so they can hear themselves.
    func startVoiceCheck() {
        guard voiceCheckState == .idle else { return }

        // Start passthrough if not already running
        if !isRunning {
            start()
        }

        recordedVoiceSamples.removeAll(keepingCapacity: true)
        isVoiceCheckRecording = true
        var remaining = 5
        voiceCheckState = .recording(secondsRemaining: remaining)

        voiceCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            remaining -= 1
            if remaining > 0 {
                self.voiceCheckState = .recording(secondsRemaining: remaining)
            } else {
                timer.invalidate()
                self.isVoiceCheckRecording = false
                self.playVoiceCheck()
            }
        }
    }

    private func playVoiceCheck() {
        guard !recordedVoiceSamples.isEmpty else {
            voiceCheckState = .idle
            return
        }

        let frameCount = AVAudioFrameCount(recordedVoiceSamples.count)
        let format = AVAudioFormat(standardFormatWithSampleRate: currentSampleRate, channels: 1)!
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            voiceCheckState = .idle
            return
        }

        pcmBuffer.frameLength = frameCount
        if let channelData = pcmBuffer.floatChannelData?[0] {
            recordedVoiceSamples.withUnsafeBufferPointer { ptr in
                channelData.update(from: ptr.baseAddress!, count: Int(frameCount))
            }
        }

        var playRemaining = max(1, Int(ceil(Double(frameCount) / currentSampleRate)))
        voiceCheckState = .playing(secondsRemaining: playRemaining)

        playerNode.scheduleBuffer(pcmBuffer, at: nil, options: []) { [weak self] in
            DispatchQueue.main.async {
                self?.voiceCheckState = .idle
            }
        }
        playerNode.play()

        voiceCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            playRemaining -= 1
            if playRemaining > 0 {
                self.voiceCheckState = .playing(secondsRemaining: playRemaining)
            } else {
                timer.invalidate()
            }
        }
    }

    /// Cancels any active voice check recording or playback.
    func cancelVoiceCheck() {
        isVoiceCheckRecording = false
        playerNode.stop()
        voiceCheckTimer?.invalidate()
        voiceCheckTimer = nil
        voiceCheckState = .idle
    }

    // MARK: - Studio Vocal Enhancer (EQ & Reverb & Echo)

    private func configureEffectDefaults() {
        delayNode.delayTime = 0.12 // 120 ms slapback
        delayNode.feedback = 25.0  // 25% repeat
        delayNode.wetDryMix = Float(echoMix)
        delayNode.bypass = echoMix <= 0.0

        reverbNode.loadFactoryPreset(reverbPreset.avPreset)
        reverbNode.wetDryMix = Float(reverbMix)
        reverbNode.bypass = reverbMix <= 0.0
    }

    /// Selects a studio vocal preset and applies immediate, polished sound.
    func setVoiceMode(_ mode: VoiceMode) {
        voiceMode = mode
        switch mode {
        case .normal:
            vocalClarity = 0.0
            reverbMix = 0.0
            echoMix = 0.0
            bassGain = 0.0
            midGain = 0.0
            trebleGain = 0.0
        case .karaoke:
            vocalClarity = 65.0
            reverbPreset = .karaokeHall
            reverbMix = 35.0
            echoMix = 15.0
            bassGain = 1.0
            midGain = 0.0
            trebleGain = 2.0
        case .studio:
            vocalClarity = 85.0
            reverbPreset = .studioRoom
            reverbMix = 22.0
            echoMix = 0.0
            bassGain = 0.5
            midGain = -1.0
            trebleGain = 3.5
        case .warmAcoustic:
            vocalClarity = 40.0
            reverbPreset = .studioRoom
            reverbMix = 28.0
            echoMix = 0.0
            bassGain = 3.5
            midGain = 1.0
            trebleGain = 0.5
        case .concert:
            vocalClarity = 60.0
            reverbPreset = .concertArena
            reverbMix = 55.0
            echoMix = 20.0
            bassGain = 1.5
            midGain = 0.0
            trebleGain = 2.5
        }
        updateEffects()
    }

    /// Updates the Vocal Clarity & Air slider (0% to 100%).
    func updateVocalClarity(_ clarity: Double) {
        vocalClarity = clarity
        updateEQParameters()
    }

    func updateTone(bass: Double, mid: Double, treble: Double) {
        bassGain = bass
        midGain = mid
        trebleGain = treble
        updateEQParameters()
    }

    func updateReverbMix(_ mix: Double) {
        reverbMix = mix
        reverbNode.wetDryMix = Float(mix)
        reverbNode.bypass = mix <= 0.0
    }

    func updateReverbPreset(_ preset: ReverbPresetOption) {
        reverbPreset = preset
        if reverbMix < 10.0 {
            reverbMix = 35.0
        }
        updateEffects()
    }

    func updateEchoMix(_ mix: Double) {
        echoMix = mix
        delayNode.wetDryMix = Float(mix)
        delayNode.bypass = mix <= 0.0
    }

    /// Resets all effects back to normal direct sound.
    func resetVoiceEffects() {
        setVoiceMode(.normal)
    }

    private func updateEffects() {
        reverbNode.loadFactoryPreset(reverbPreset.avPreset)
        reverbNode.wetDryMix = Float(reverbMix)
        reverbNode.bypass = reverbMix <= 0.0

        delayNode.delayTime = 0.12
        delayNode.feedback = 25.0
        delayNode.wetDryMix = Float(echoMix)
        delayNode.bypass = echoMix <= 0.0

        updateEQParameters()
    }

    private func updateEQParameters() {
        let clarityFactor = Float(vocalClarity / 100.0) // 0.0 to 1.0

        if creativeVoiceMode == .walkieTalkie {
            // Bandpass filter simulation for Walkie-Talkie
            eqNode.bands[0].filterType = .highPass
            eqNode.bands[0].frequency = 450.0
            eqNode.bands[1].gain = -6.0 // Cut low
            eqNode.bands[2].gain = 4.0  // Boost mid punch
            eqNode.bands[3].gain = 5.0  // High crackle
            eqNode.bands[4].gain = -8.0 // Cut ultra-high air
            eqNode.bypass = false
            return
        }

        if creativeVoiceMode == .vintagePhone {
            // Bandpass filter simulation for Vintage Telephone (300Hz - 3400Hz)
            eqNode.bands[0].filterType = .highPass
            eqNode.bands[0].frequency = 350.0
            eqNode.bands[1].gain = -5.0
            eqNode.bands[2].gain = 3.0
            eqNode.bands[3].gain = -2.0
            eqNode.bands[4].gain = -12.0
            eqNode.bypass = false
            return
        }

        if creativeVoiceMode == .megaphone {
            // Megaphone Horn resonance
            eqNode.bands[0].filterType = .highPass
            eqNode.bands[0].frequency = 300.0
            eqNode.bands[1].gain = -4.0
            eqNode.bands[2].gain = 6.0  // Heavy 500Hz-1kHz horn presence
            eqNode.bands[3].gain = 4.0
            eqNode.bands[4].gain = -6.0
            eqNode.bypass = false
            return
        }

        // Standard Studio Vocal EQ
        eqNode.bands[0].filterType = .highPass
        eqNode.bands[0].frequency = 80.0

        // Band 1: Vocal Warmth (Low Shelf @ 220Hz) + User Bass Gain
        let baseWarmth = voiceMode == .warmAcoustic ? 3.5 : (1.0 * clarityFactor)
        eqNode.bands[1].gain = Float(baseWarmth) + Float(bassGain)

        // Band 2: De-Mud @ 500Hz + User Mid Gain
        let deMud = -4.5 * clarityFactor
        eqNode.bands[2].gain = Float(deMud) + Float(midGain)

        // Band 3: Vocal Presence @ 3500Hz + User Treble Gain
        let presence = 5.5 * clarityFactor
        eqNode.bands[3].gain = Float(presence) + Float(trebleGain)

        // Band 4: High Air Sparkle @ 10,000Hz
        let air = 7.0 * clarityFactor
        eqNode.bands[4].gain = Float(air) + Float(trebleGain * 0.5)

        // Auto bypass EQ if completely flat to save DSP render time
        let isFlat = vocalClarity <= 0.0 && bassGain == 0.0 && midGain == 0.0 && trebleGain == 0.0 && voiceMode == .normal
        eqNode.bypass = isFlat
    }

    // MARK: - Buffer Size & Latency Control

    /// Changes the hardware I/O buffer frame size and reapplies to hardware.
    func updateBufferSize(_ newSize: UInt32) {
        bufferSize = newSize
        applyHardwareBufferSize(newSize)

        if isRunning {
            stop()
            start()
        }
    }

    // MARK: - Audio Level Meter Tap & Real-time DSP

    private func installAudioMeterTap(on inputNode: AVAudioInputNode, format: AVAudioFormat) {
        guard !isTapInstalled else { return }

        let tapBufferSize: AVAudioFrameCount = 512

        inputNode.installTap(onBus: 0, bufferSize: tapBufferSize, format: format) { [weak self] buffer, _ in
            guard let self = self else { return }
            guard let channelData = buffer.floatChannelData?[0] else { return }
            let frameCount = Int(buffer.frameLength)
            guard frameCount > 0 else { return }

            // 1. Calculate RMS energy
            var sum: Float = 0
            for i in 0..<frameCount {
                let sample = channelData[i]
                sum += sample * sample
            }
            let rms = sqrt(sum / Float(frameCount))
            let normalized = min(max(rms * 4.0, 0.0), 1.0)

            // 2. Smart Noise Gate Calculation
            if self.isNoiseGateEnabled {
                // Map sensitivity (0% - 100%) to threshold RMS (0.0005 to 0.02)
                let gateThreshold = Float(0.0005 + (self.noiseGateSensitivity / 100.0) * 0.015)
                if rms < gateThreshold {
                    // Smooth 100ms decay to 0 (No click)
                    self.currentGateGain = max(0.0, self.currentGateGain * 0.85)
                } else {
                    // Fast 5ms attack to 1.0
                    self.currentGateGain = min(1.0, self.currentGateGain + 0.3)
                }
                let open = self.currentGateGain > 0.05
                DispatchQueue.main.async {
                    self.isGateOpen = open
                    self.applyEffectiveGain()
                }
            } else {
                if self.currentGateGain != 1.0 {
                    self.currentGateGain = 1.0
                    DispatchQueue.main.async {
                        self.isGateOpen = true
                        self.applyEffectiveGain()
                    }
                }
            }

            // 3. 5-Second Voice Check in-memory recorder
            if self.isVoiceCheckRecording {
                let maxFrames = Int(self.currentSampleRate * 5.0)
                let toCopy = min(frameCount, maxFrames - self.recordedVoiceSamples.count)
                if toCopy > 0 {
                    self.recordedVoiceSamples.append(contentsOf: UnsafeBufferPointer(start: channelData, count: toCopy))
                }
            }

            DispatchQueue.main.async {
                self.audioLevel = normalized
            }
        }
        isTapInstalled = true
    }

    private func removeAudioMeterTap() {
        if isTapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            isTapInstalled = false
        }
    }

    // MARK: - Hotkeys Setup (Option + M & Spacebar)

    private func setupHotkeys() {
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.modifierFlags.contains(.option) && event.charactersIgnoringModifiers?.lowercased() == "m" {
                self?.toggleMute()
                return nil
            }
            if event.keyCode == 49 && !(NSApp.keyWindow?.firstResponder is NSText) {
                self?.toggleMute()
                return nil
            }
            return event
        }

        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.modifierFlags.contains(.option) && event.charactersIgnoringModifiers?.lowercased() == "m" {
                DispatchQueue.main.async {
                    self?.toggleMute()
                }
            }
        }
    }

    // MARK: - Configuration Change Notification

    private func registerConfigurationChangeListener() {
        configChangeObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            self.refreshDevices()
            if self.isRunning {
                self.stop()
                self.start()
            }
        }
    }

    // MARK: - CoreAudio Hardware Helpers

    private func applyHardwareBufferSize(_ frames: UInt32) {
        let inID = selectedInputDeviceID != 0 ? selectedInputDeviceID : getDefaultDeviceID(isInput: true)
        let outID = selectedOutputDeviceID != 0 ? selectedOutputDeviceID : getDefaultDeviceID(isInput: false)

        var size = frames
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyBufferFrameSize,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let propSize = UInt32(MemoryLayout<UInt32>.size)

        if inID != 0 {
            _ = AudioObjectSetPropertyData(inID, &address, 0, nil, propSize, &size)
        }
        if outID != 0 {
            _ = AudioObjectSetPropertyData(outID, &address, 0, nil, propSize, &size)
        }
    }

    private func getDefaultDeviceID(isInput: Bool) -> AudioDeviceID {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: isInput ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
        return status == noErr ? deviceID : 0
    }

    // MARK: - CoreAudio Device Enumeration

    static func queryAllDevices() -> [AudioDevice] {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &dataSize)
        guard status == noErr, dataSize > 0 else { return [] }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &dataSize, &deviceIDs)
        guard status == noErr else { return [] }

        return deviceIDs.compactMap { id -> AudioDevice? in
            var name: CFString = "" as CFString
            var propSize = UInt32(MemoryLayout<CFString>.size)
            var nameAddr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceNameCFString,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            let nameStatus = withUnsafeMutablePointer(to: &name) { ptr in
                AudioObjectGetPropertyData(id, &nameAddr, 0, nil, &propSize, ptr)
            }
            guard nameStatus == noErr else { return nil }

            func getChannelCount(scope: AudioObjectPropertyScope) -> Int {
                var streamAddr = AudioObjectPropertyAddress(
                    mSelector: kAudioDevicePropertyStreamConfiguration,
                    mScope: scope,
                    mElement: kAudioObjectPropertyElementMain
                )
                var streamSize: UInt32 = 0
                guard AudioObjectGetPropertyDataSize(id, &streamAddr, 0, nil, &streamSize) == noErr, streamSize > 0 else { return 0 }
                let bufferListPtr = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
                defer { bufferListPtr.deallocate() }
                guard AudioObjectGetPropertyData(id, &streamAddr, 0, nil, &streamSize, bufferListPtr) == noErr else { return 0 }
                let abl = UnsafeMutableAudioBufferListPointer(bufferListPtr)
                return abl.reduce(0) { $0 + Int($1.mNumberChannels) }
            }

            let inCh = getChannelCount(scope: kAudioDevicePropertyScopeInput)
            let outCh = getChannelCount(scope: kAudioDevicePropertyScopeOutput)
            guard inCh > 0 || outCh > 0 else { return nil }

            return AudioDevice(id: id, name: name as String, isInput: inCh > 0, isOutput: outCh > 0)
        }
    }

    // MARK: - Hardware Listeners

    private func registerHardwareListeners() {
        guard !hardwareListenerRegistered else { return }

        var devAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        _ = AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &devAddress, DispatchQueue.main) { [weak self] _, _ in
            self?.refreshDevices()
        }

        hardwareListenerRegistered = true
    }

    private func unregisterHardwareListeners() {
        hardwareListenerRegistered = false
    }
}
