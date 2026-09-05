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

// MARK: - Reverb Preset Enum

enum VoiceMode: String, CaseIterable, Identifiable {
    case normal = "Normal (Off)"
    case karaoke = "🎤 Karaoke"
    case studio = "🎙️ Studio"
    case concert = "🏛️ Concert"

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

/// Manages the low-latency audio engine for real-time microphone passthrough.
/// Responsible for:
/// 1. Querying and selecting hardware input/output devices directly in-app.
/// 2. Configuring low-latency hardware buffer frame sizes (32, 64, 128, 256 samples).
/// 3. Connecting AVAudioEngine inputNode -> GainMixer -> Delay (Echo) -> Reverb -> mainMixerNode -> outputNode.
/// 4. Measuring live audio input level for UI feedback.
/// 5. Providing instantaneous Mute and Global/Local Hotkey controls.
/// 6. Real-time karaoke voice effects (Reverb & Echo).
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

    // MARK: - Published Karaoke Effects
    @Published var voiceMode: VoiceMode = .normal
    @Published var reverbMix: Double = 0.0 // 0.0 to 100.0 (0% = Dry, 100% = Wet)
    @Published var reverbPreset: ReverbPresetOption = .karaokeHall
    @Published var echoMix: Double = 0.0 // 0.0 to 50.0 (0% = Off, 50% = Max Echo)

    // MARK: - Internal Audio Nodes
    private let engine = AVAudioEngine()
    private let gainMixer = AVAudioMixerNode()
    private let delayNode = AVAudioUnitDelay()
    private let reverbNode = AVAudioUnitReverb()
    private var isTapInstalled = false

    // Event & Notification Observers
    private var hardwareListenerRegistered = false
    private var configChangeObserver: NSObjectProtocol?
    private var localKeyMonitor: Any?
    private var globalKeyMonitor: Any?

    init() {
        // STEP 1: Attach audio nodes to engine graph
        engine.attach(gainMixer)
        engine.attach(delayNode)
        engine.attach(reverbNode)

        // Configure initial effect parameters
        configureEffectDefaults()

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

    // MARK: - Device Detection & Monitoring

    /// Refreshes all available macOS input and output devices.
    func refreshDevices() {
        let allDevices = Self.queryAllDevices()
        let inputs = allDevices.filter { $0.isInput }
        let outputs = allDevices.filter { $0.isOutput }

        let defaultInID = getDefaultDeviceID(isInput: true)
        let defaultOutID = getDefaultDeviceID(isInput: false)

        DispatchQueue.main.async {
            self.availableInputDevices = inputs
            self.availableOutputDevices = outputs

            // If selected device is not set or no longer present, fallback to default
            if self.selectedInputDeviceID == 0 || !inputs.contains(where: { $0.id == self.selectedInputDeviceID }) {
                self.selectedInputDeviceID = defaultInID
            }
            if self.selectedOutputDeviceID == 0 || !outputs.contains(where: { $0.id == self.selectedOutputDeviceID }) {
                self.selectedOutputDeviceID = defaultOutID
            }

            // Check if selected input is Bluetooth (e.g. Willen/Headset) to warn about delay/HFP mode
            let currentInName = inputs.first(where: { $0.id == self.selectedInputDeviceID })?.name.lowercased() ?? ""
            self.isBluetoothInputWarning = currentInName.contains("willen") || currentInName.contains("bluetooth")
        }
    }

    /// Selects an input device and reapplies it to the audio engine.
    func selectInputDevice(id: AudioDeviceID) {
        guard id != 0 else { return }
        selectedInputDeviceID = id

        var devID = id
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
            &devID
        )

        let currentInName = availableInputDevices.first(where: { $0.id == id })?.name.lowercased() ?? ""
        isBluetoothInputWarning = currentInName.contains("willen") || currentInName.contains("bluetooth")

        if isRunning {
            stop()
            start()
        }
    }

    /// Selects an output device and reapplies it to the audio engine.
    func selectOutputDevice(id: AudioDeviceID) {
        guard id != 0 else { return }
        selectedOutputDeviceID = id

        var devID = id
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
            &devID
        )

        if isRunning {
            stop()
            start()
        }
    }

    // MARK: - Permissions

    private func checkMicrophonePermission(completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    completion(granted)
                }
            }
        case .denied, .restricted:
            completion(false)
        @unknown default:
            completion(false)
        }
    }

    // MARK: - Engine Lifecycle

    /// Starts live microphone passthrough with low-latency configuration.
    func start() {
        guard !isRunning else { return }
        errorMessage = nil

        // STEP 1: Verify microphone permission
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

        // STEP 2: Disconnect any previous connections to ensure a clean slate
        engine.disconnectNodeOutput(inputNode)
        engine.disconnectNodeInput(gainMixer)
        engine.disconnectNodeOutput(gainMixer)
        engine.disconnectNodeInput(delayNode)
        engine.disconnectNodeOutput(delayNode)
        engine.disconnectNodeInput(reverbNode)
        engine.disconnectNodeOutput(reverbNode)

        // STEP 4: Retrieve valid outputFormat from inputNode
        var inputFormat = inputNode.outputFormat(forBus: 0)

        // If audio unit was cold and returns 0 sample rate / channels, reset and re-query
        if inputFormat.sampleRate == 0 || inputFormat.channelCount == 0 {
            engine.reset()
            inputFormat = inputNode.outputFormat(forBus: 0)
        }

        guard inputFormat.sampleRate > 0 && inputFormat.channelCount > 0 else {
            errorMessage = "No microphone input detected. Please verify microphone in System Settings > Sound."
            return
        }

        // STEP 5: Connect audio chain: inputNode -> gainMixer -> delayNode -> reverbNode -> mainMixerNode
        engine.connect(inputNode, to: gainMixer, format: inputFormat)
        engine.connect(gainMixer, to: delayNode, format: nil)
        engine.connect(delayNode, to: reverbNode, format: nil)
        engine.connect(reverbNode, to: engine.mainMixerNode, format: nil)

        // Apply initial volume & mute state
        gainMixer.outputVolume = isMuted ? 0.0 : Float(gain)

        // Update effect node settings
        updateEffects()

        // STEP 6: Install audio tap directly on inputNode for accurate live RMS metering
        installAudioMeterTap(on: inputNode, format: inputFormat)

        // STEP 7: Prepare and start audio engine
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
        engine.stop()
        engine.disconnectNodeOutput(engine.inputNode)
        engine.disconnectNodeInput(gainMixer)
        engine.disconnectNodeOutput(gainMixer)
        engine.disconnectNodeInput(delayNode)
        engine.disconnectNodeOutput(delayNode)
        engine.disconnectNodeInput(reverbNode)
        engine.disconnectNodeOutput(reverbNode)
        engine.reset()
        isRunning = false
        audioLevel = 0.0
    }

    // MARK: - Gain & Mute Controls

    /// Updates the volume gain multiplier (0.0 to 2.0 = 0% to 200%).
    func updateGain(_ newGain: Double) {
        gain = newGain
        if !isMuted {
            gainMixer.outputVolume = Float(newGain)
        }
    }

    /// Toggles the Mute state instantly.
    func toggleMute() {
        isMuted.toggle()
        if isMuted {
            gainMixer.outputVolume = 0.0
        } else {
            gainMixer.outputVolume = Float(gain)
        }
    }

    // MARK: - Voice Effects (Karaoke Reverb & Echo)

    private func configureEffectDefaults() {
        delayNode.delayTime = 0.12 // 120 ms slapback
        delayNode.feedback = 25.0  // 25% repeat
        delayNode.wetDryMix = Float(echoMix)

        reverbNode.loadFactoryPreset(reverbPreset.avPreset)
        reverbNode.wetDryMix = Float(reverbMix)
    }

    /// Selects a voice mode and applies immediate, audible effect parameters.
    func setVoiceMode(_ mode: VoiceMode) {
        voiceMode = mode
        switch mode {
        case .normal:
            reverbMix = 0.0
            echoMix = 0.0
        case .karaoke:
            reverbPreset = .karaokeHall
            reverbMix = 35.0
            echoMix = 15.0
        case .studio:
            reverbPreset = .studioRoom
            reverbMix = 20.0
            echoMix = 0.0
        case .concert:
            reverbPreset = .concertArena
            reverbMix = 60.0
            echoMix = 20.0
        }
        updateEffects()
    }

    func updateReverbMix(_ mix: Double) {
        reverbMix = mix
        reverbNode.wetDryMix = Float(mix)
    }

    func updateReverbPreset(_ preset: ReverbPresetOption) {
        reverbPreset = preset
        // If reverb is currently 0, boost to 35% so the user immediately hears the new acoustic space
        if reverbMix < 10.0 {
            reverbMix = 35.0
        }
        updateEffects()
    }

    func updateEchoMix(_ mix: Double) {
        echoMix = mix
        delayNode.wetDryMix = Float(mix)
    }

    /// Clears voice effects back to pure direct voice.
    func resetVoiceEffects() {
        setVoiceMode(.normal)
    }

    private func updateEffects() {
        reverbNode.loadFactoryPreset(reverbPreset.avPreset)
        reverbNode.wetDryMix = Float(reverbMix)
        delayNode.delayTime = 0.12
        delayNode.feedback = 25.0
        delayNode.wetDryMix = Float(echoMix)
    }

    // MARK: - Buffer Size & Latency Control

    /// Changes the hardware I/O buffer frame size and reapplies to hardware.
    func updateBufferSize(_ newSize: UInt32) {
        bufferSize = newSize
        applyHardwareBufferSize(newSize)

        // If running, restart engine so it adopts new buffer frames smoothly
        if isRunning {
            stop()
            start()
        }
    }

    // MARK: - Audio Level Meter

    private func installAudioMeterTap(on inputNode: AVAudioInputNode, format: AVAudioFormat) {
        guard !isTapInstalled else { return }

        let tapBufferSize: AVAudioFrameCount = 512
        inputNode.installTap(onBus: 0, bufferSize: tapBufferSize, format: format) { [weak self] buffer, _ in
            guard let channelData = buffer.floatChannelData?[0] else { return }
            let frameCount = Int(buffer.frameLength)
            guard frameCount > 0 else { return }

            var sum: Float = 0
            for i in 0..<frameCount {
                let sample = channelData[i]
                sum += sample * sample
            }
            let rms = sqrt(sum / Float(frameCount))
            let normalized = min(max(rms * 4.0, 0.0), 1.0)

            DispatchQueue.main.async {
                self?.audioLevel = normalized
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
        // Local Monitor: Works whenever the app window is active
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Check for Option + M
            if event.modifierFlags.contains(.option) && event.charactersIgnoringModifiers?.lowercased() == "m" {
                self?.toggleMute()
                return nil
            }
            // Check for Spacebar (only if user is not editing a text input)
            if event.keyCode == 49 && !(NSApp.keyWindow?.firstResponder is NSText) {
                self?.toggleMute()
                return nil
            }
            return event
        }

        // Global Monitor: Works system-wide when other apps are in focus
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
