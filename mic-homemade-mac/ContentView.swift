import SwiftUI
import CoreAudio

/// Main UI Screen for mic-homemade-mac.
/// Follows modular, small-widget design with rich studio vocal features.
/// All non-core/advanced features are tucked cleanly inside a collapsible drawer.
struct ContentView: View {
    @StateObject private var audio = AudioEngineManager()
    @State private var isAdvancedExpanded = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Header: App Title & Icon
                HeaderSection()

                // Device Selection: Input & Output Dropdowns
                DeviceSelectorSection(audio: audio)

                // Warning Banner if Bluetooth is selected as Input
                if audio.isBluetoothInputWarning {
                    BluetoothInputWarningView()
                }

                // 5-Second Voice Check Preview Banner (Core Feature)
                VoiceCheckSection(audio: audio)

                // Live Audio Level Meter (Core Feature)
                if audio.isRunning {
                    AudioLevelMeterView(
                        level: audio.audioLevel,
                        isMuted: audio.isMuted,
                        isGateOpen: audio.isGateOpen,
                        isGateEnabled: audio.isNoiseGateEnabled
                    )
                }

                // Mute Toggle & Gain Control (Core Feature)
                AudioControlSection(audio: audio)

                // Studio Vocal Enhancer - Presets, Clarity, Reverb, Echo (Core Feature)
                StudioVocalEnhancerSection(audio: audio)

                // Collapsible Advanced Settings (Non-core features: Compressor, Creative FX, Noise Gate, Tone, Latency)
                AdvancedSettingsSection(audio: audio, isExpanded: $isAdvancedExpanded)

                // Error Display (if any)
                if let error = audio.errorMessage {
                    ErrorMessageView(message: error)
                }

                // Main START / STOP Action Button (Core Feature)
                ControlActionButton(isRunning: audio.isRunning) {
                    if audio.isRunning {
                        audio.stop()
                    } else {
                        audio.start()
                    }
                }

                // Footer Subtitle
                FooterSubtitleView()
            }
            .padding(20)
        }
        .frame(width: 440, height: 750)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Header Section

private struct HeaderSection: View {
    private var appIconImage: NSImage? {
        if let path = Bundle.main.path(forResource: "AppIcon", ofType: "icns") {
            return NSImage(contentsOfFile: path)
        }
        return nil
    }

    var body: some View {
        HStack(spacing: 12) {
            if let icon = appIconImage {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                    .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
            } else {
                Text("🎤")
                    .font(.largeTitle)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("mic-homemade-mac")
                    .font(.headline)
                    .fontWeight(.bold)
                    .tracking(0.8)
                Text("Ultra-Low Latency Live Passthrough & Studio Suite")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Device Selector Section

private struct DeviceSelectorSection: View {
    @ObservedObject var audio: AudioEngineManager

    var body: some View {
        VStack(spacing: 10) {
            // Input Device Picker
            HStack {
                Label("Input", systemImage: "mic.fill")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.blue)
                    .frame(width: 75, alignment: .leading)

                Picker("", selection: Binding(
                    get: { audio.selectedInputDeviceID },
                    set: { audio.selectInputDevice(id: $0) }
                )) {
                    ForEach(audio.availableInputDevices) { device in
                        Text(device.name).tag(device.id)
                    }
                }
                .labelsHidden()
            }

            Divider()

            // Output Device Picker
            HStack {
                Label("Output", systemImage: "speaker.wave.3.fill")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.purple)
                    .frame(width: 75, alignment: .leading)

                Picker("", selection: Binding(
                    get: { audio.selectedOutputDeviceID },
                    set: { audio.selectOutputDevice(id: $0) }
                )) {
                    ForEach(audio.availableOutputDevices) { device in
                        Text(device.name).tag(device.id)
                    }
                }
                .labelsHidden()
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Bluetooth Input Warning

private struct BluetoothInputWarningView: View {
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Bluetooth Input Detected")
                    .font(.caption)
                    .fontWeight(.semibold)
                Text("Bluetooth mic introduces ~150ms delay. Select USB Mic or Built-in Mic for true real-time passthrough.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(Color.orange.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - 5-Second Voice Check Section

private struct VoiceCheckSection: View {
    @ObservedObject var audio: AudioEngineManager

    var body: some View {
        HStack {
            switch audio.voiceCheckState {
            case .idle:
                Button {
                    audio.startVoiceCheck()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "waveform.badge.mic")
                            .font(.caption)
                        Text("5s Voice Check (Test Mic)")
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(Color.blue.opacity(0.12))
                    .foregroundStyle(.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)

            case .recording(let remaining):
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                    Text("Recording voice test... \(remaining)s (Sing or speak now)")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.red)
                    Spacer()
                    Button("Cancel") {
                        audio.cancelVoiceCheck()
                    }
                    .font(.caption2)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color.red.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            case .playing(let remaining):
                HStack(spacing: 8) {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                    Text("Playing back your voice... \(remaining)s")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.green)
                    Spacer()
                    Button("Stop") {
                        audio.cancelVoiceCheck()
                    }
                    .font(.caption2)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color.green.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}

// MARK: - Live Audio Level Meter

private struct AudioLevelMeterView: View {
    let level: Float
    let isMuted: Bool
    let isGateOpen: Bool
    let isGateEnabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(isMuted ? "LIVE INPUT LEVEL (MUTED)" : "LIVE INPUT LEVEL")
                    .font(.caption2)
                    .foregroundStyle(isMuted ? .red : .secondary)
                    .fontWeight(.semibold)

                Spacer()

                if isGateEnabled && !isMuted {
                    Text(isGateOpen ? "GATE: OPEN" : "GATE: QUIET")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(isGateOpen ? .green : .secondary)
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.secondary.opacity(0.2))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(
                            isMuted
                            ? LinearGradient(colors: [.red.opacity(0.5), .red], startPoint: .leading, endPoint: .trailing)
                            : LinearGradient(colors: [.green, .yellow, .red], startPoint: .leading, endPoint: .trailing)
                        )
                        .frame(width: geo.size.width * CGFloat(level))
                        .animation(.easeOut(duration: 0.08), value: level)
                }
            }
            .frame(height: 6)
        }
    }
}

// MARK: - Audio Control (Gain & Mute)

private struct AudioControlSection: View {
    @ObservedObject var audio: AudioEngineManager

    var body: some View {
        HStack(spacing: 12) {
            // Instant Mute Button
            Button {
                audio.toggleMute()
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: audio.isMuted ? "mic.slash.fill" : "mic.fill")
                        .font(.title3)
                    Text(audio.isMuted ? "MUTED" : "MUTE")
                        .font(.caption2)
                        .fontWeight(.bold)
                    Text("⌥M")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(audio.isMuted ? Color.white.opacity(0.8) : Color.secondary)
                }
                .frame(width: 70, height: 60)
                .background(audio.isMuted ? Color.red : Color(nsColor: .controlBackgroundColor))
                .foregroundStyle(audio.isMuted ? Color.white : Color.primary)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)

            // Gain Slider (0% - 200%)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("VOLUME GAIN")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(audio.gain * 100))%")
                        .font(.subheadline)
                        .monospacedDigit()
                        .bold()
                }

                Slider(value: $audio.gain, in: 0.0...2.0, step: 0.05) {
                    Text("Gain")
                } minimumValueLabel: {
                    Text("0%").font(.caption2).foregroundStyle(.secondary)
                } maximumValueLabel: {
                    Text("200%").font(.caption2).foregroundStyle(.secondary)
                }
                .onChange(of: audio.gain) { newValue in
                    audio.updateGain(newValue)
                }
            }
            .padding(10)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

// MARK: - Studio Vocal Enhancer Section (Core Feature)

private struct StudioVocalEnhancerSection: View {
    @ObservedObject var audio: AudioEngineManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section Header
            HStack {
                Label("STUDIO VOCAL ENHANCER", systemImage: "sparkles")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)
                Spacer()
                if audio.vocalClarity > 0 || audio.reverbMix > 0 || audio.echoMix > 0 {
                    Text("ENHANCER ACTIVE")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.green)
                }
            }

            // Quick Voice Preset Buttons Grid
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    ForEach([VoiceMode.normal, VoiceMode.karaoke, VoiceMode.studio]) { mode in
                        PresetButton(mode: mode, selectedMode: audio.voiceMode) {
                            audio.setVoiceMode(mode)
                        }
                    }
                }
                HStack(spacing: 6) {
                    ForEach([VoiceMode.warmAcoustic, VoiceMode.concert]) { mode in
                        PresetButton(mode: mode, selectedMode: audio.voiceMode) {
                            audio.setVoiceMode(mode)
                        }
                    }
                }
            }

            Divider()

            // Fine-Tuning Sliders
            // 1. Vocal Clarity & Air
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Label("Vocal Clarity & Air:", systemImage: "waveform.badge.magnifyingglass")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text("\(Int(audio.vocalClarity))%")
                        .font(.caption2)
                        .monospacedDigit()
                        .bold()
                        .foregroundStyle(audio.vocalClarity > 0 ? .blue : .secondary)
                }

                Slider(
                    value: Binding(
                        get: { audio.vocalClarity },
                        set: { audio.updateVocalClarity($0) }
                    ),
                    in: 0.0...100.0,
                    step: 5.0
                )
            }

            // 2. Reverb Room Preset & Intensity Slider
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Label("Reverb Space (\(audio.reverbPreset.rawValue)):", systemImage: "building.columns.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text("\(Int(audio.reverbMix))%")
                        .font(.caption2)
                        .monospacedDigit()
                        .bold()
                        .foregroundStyle(audio.reverbMix > 0 ? .purple : .secondary)
                }

                Slider(
                    value: Binding(
                        get: { audio.reverbMix },
                        set: { audio.updateReverbMix($0) }
                    ),
                    in: 0.0...100.0,
                    step: 5.0
                )
            }

            // 3. Vocal Echo Slider
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Label("Vocal Echo (Repeat):", systemImage: "repeat")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text("\(Int(audio.echoMix))%")
                        .font(.caption2)
                        .monospacedDigit()
                        .bold()
                        .foregroundStyle(audio.echoMix > 0 ? .teal : .secondary)
                }

                Slider(
                    value: Binding(
                        get: { audio.echoMix },
                        set: { audio.updateEchoMix($0) }
                    ),
                    in: 0.0...50.0,
                    step: 5.0
                )
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct PresetButton: View {
    let mode: VoiceMode
    let selectedMode: VoiceMode
    let action: () -> Void

    private var isSelected: Bool {
        mode == selectedMode
    }

    var body: some View {
        Button(action: action) {
            Text(mode.rawValue)
                .font(.caption)
                .fontWeight(isSelected ? .bold : .regular)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(
                    isSelected
                    ? Color.accentColor
                    : Color(nsColor: .windowBackgroundColor)
                )
                .foregroundStyle(
                    isSelected
                    ? Color.white
                    : Color.primary
                )
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Collapsible Advanced Settings (Non-Core Features Drawer)

private struct AdvancedSettingsSection: View {
    @ObservedObject var audio: AudioEngineManager
    @Binding var isExpanded: Bool

    var body: some View {
        DisclosureGroup(
            isExpanded: $isExpanded,
            content: {
                VStack(spacing: 12) {
                    // 1. Studio Vocal Compressor (Auto Leveling)
                    CompressorControlView(audio: audio)

                    // 2. Creative Sound Effects (Radio, Megaphone, Telephone, Alien)
                    CreativeVoiceControlView(audio: audio)

                    // 3. Smart Noise Gate
                    NoiseGateControlView(audio: audio)

                    // 4. Manual 3-Band Tone (Bass / Mid / Treble)
                    ManualToneControlView(audio: audio)

                    // 5. Latency Hardware Buffer Frame Selector
                    BufferSelectorSection(selectedBuffer: audio.bufferSize) { newBuffer in
                        audio.updateBufferSize(newBuffer)
                    }
                }
                .padding(.top, 8)
            },
            label: {
                Label("Advanced Settings & Sound FX", systemImage: "slider.horizontal.3")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
            }
        )
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Studio Vocal Compressor Control View

private struct CompressorControlView: View {
    @ObservedObject var audio: AudioEngineManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Studio Vocal Compressor", systemImage: "waveform.path.ecg")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)

                Spacer()

                Toggle("", isOn: Binding(
                    get: { audio.isCompressorEnabled },
                    set: { audio.updateCompressor(enabled: $0, profile: audio.compressorProfile) }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                .scaleEffect(0.75)
            }

            if audio.isCompressorEnabled {
                Text("Auto-levels quiet speech & prevents loud shouting from clipping.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)

                HStack(spacing: 4) {
                    ForEach(CompressorProfile.allCases) { profile in
                        Button {
                            audio.updateCompressor(enabled: true, profile: profile)
                        } label: {
                            Text(profile.rawValue)
                                .font(.system(size: 9, weight: audio.compressorProfile == profile ? .bold : .regular))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 5)
                                .background(
                                    audio.compressorProfile == profile
                                    ? Color.accentColor
                                    : Color(nsColor: .controlBackgroundColor)
                                )
                                .foregroundStyle(audio.compressorProfile == profile ? Color.white : Color.primary)
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(8)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Creative Sound FX Control View

private struct CreativeVoiceControlView: View {
    @ObservedObject var audio: AudioEngineManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Creative Sound Effects", systemImage: "radio.fill")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)

                Spacer()

                if audio.creativeVoiceMode != .off {
                    Text("FX ACTIVE")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.orange)
                }
            }

            VStack(spacing: 5) {
                HStack(spacing: 5) {
                    ForEach([CreativeVoiceMode.off, CreativeVoiceMode.walkieTalkie]) { mode in
                        CreativeFXButton(mode: mode, selectedMode: audio.creativeVoiceMode) {
                            audio.setCreativeVoiceMode(mode)
                        }
                    }
                }
                HStack(spacing: 5) {
                    ForEach([CreativeVoiceMode.megaphone, CreativeVoiceMode.vintagePhone, CreativeVoiceMode.alien]) { mode in
                        CreativeFXButton(mode: mode, selectedMode: audio.creativeVoiceMode) {
                            audio.setCreativeVoiceMode(mode)
                        }
                    }
                }
            }
        }
        .padding(8)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

private struct CreativeFXButton: View {
    let mode: CreativeVoiceMode
    let selectedMode: CreativeVoiceMode
    let action: () -> Void

    private var isSelected: Bool {
        mode == selectedMode
    }

    var body: some View {
        Button(action: action) {
            Text(mode.rawValue)
                .font(.system(size: 10, weight: isSelected ? .bold : .regular))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background(
                    isSelected
                    ? (mode == .off ? Color.secondary.opacity(0.3) : Color.orange)
                    : Color(nsColor: .controlBackgroundColor)
                )
                .foregroundStyle(isSelected ? (mode == .off ? Color.primary : Color.white) : Color.primary)
                .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Smart Noise Gate Control

private struct NoiseGateControlView: View {
    @ObservedObject var audio: AudioEngineManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Smart Noise Gate", systemImage: "waveform.badge.minus")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)

                Spacer()

                Toggle("", isOn: Binding(
                    get: { audio.isNoiseGateEnabled },
                    set: { audio.updateNoiseGate(enabled: $0, sensitivity: audio.noiseGateSensitivity) }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                .scaleEffect(0.75)
            }

            if audio.isNoiseGateEnabled {
                HStack {
                    Text("Room Noise Cut Sensitivity:")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text("\(Int(audio.noiseGateSensitivity))%")
                        .font(.caption2)
                        .monospacedDigit()
                        .bold()
                }

                Slider(
                    value: Binding(
                        get: { audio.noiseGateSensitivity },
                        set: { audio.updateNoiseGate(enabled: true, sensitivity: $0) }
                    ),
                    in: 5.0...100.0,
                    step: 5.0
                )
            }
        }
        .padding(8)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Manual 3-Band Tone Control

private struct ManualToneControlView: View {
    @ObservedObject var audio: AudioEngineManager

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Label("Manual 3-Band Tone", systemImage: "dial.low.fill")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            ToneSliderRow(label: "Bass (Low Body)", value: $audio.bassGain, range: -6.0...6.0) {
                audio.updateTone(bass: audio.bassGain, mid: audio.midGain, treble: audio.trebleGain)
            }
            ToneSliderRow(label: "Mid (Clarity)", value: $audio.midGain, range: -6.0...6.0) {
                audio.updateTone(bass: audio.bassGain, mid: audio.midGain, treble: audio.trebleGain)
            }
            ToneSliderRow(label: "Treble (High Air)", value: $audio.trebleGain, range: -6.0...6.0) {
                audio.updateTone(bass: audio.bassGain, mid: audio.midGain, treble: audio.trebleGain)
            }
        }
        .padding(8)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

private struct ToneSliderRow: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let onChange: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%+.1f dB", value))
                    .font(.caption2)
                    .monospacedDigit()
                    .bold()
            }
            Slider(value: $value, in: range, step: 0.5)
                .onChange(of: value) { _ in onChange() }
        }
    }
}

// MARK: - Buffer Selector Section

private struct BufferSelectorSection: View {
    let selectedBuffer: UInt32
    let onSelect: (UInt32) -> Void

    private let options: [UInt32] = [32, 64, 128, 256]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Buffer Size (Latency)", systemImage: "clock.arrow.circlepath")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(latencyEstimate(for: selectedBuffer))
                    .font(.caption2)
                    .foregroundStyle(.blue)
            }

            HStack(spacing: 8) {
                ForEach(options, id: \.self) { size in
                    Button {
                        onSelect(size)
                    } label: {
                        Text("\(size)")
                            .font(.subheadline)
                            .fontWeight(selectedBuffer == size ? .bold : .regular)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(
                                selectedBuffer == size
                                ? Color.accentColor
                                : Color(nsColor: .controlBackgroundColor)
                            )
                            .foregroundStyle(selectedBuffer == size ? Color.white : Color.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(8)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func latencyEstimate(for frames: UInt32) -> String {
        let ms = Double(frames) / 48.0
        return String(format: "~%.1f ms hardware buffer", ms)
    }
}

// MARK: - Control Action Button

private struct ControlActionButton: View {
    let isRunning: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Circle()
                    .fill(isRunning ? Color.red : Color.green)
                    .frame(width: 10, height: 10)
                Text(isRunning ? "STOP PASSTHROUGH" : "START PASSTHROUGH")
                    .fontWeight(.bold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
        .buttonStyle(.borderedProminent)
        .tint(isRunning ? .red : .blue)
        .controlSize(.large)
    }
}

// MARK: - Footer & Error Views

private struct ErrorMessageView: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.caption)
            .foregroundStyle(.red)
            .multilineTextAlignment(.center)
    }
}

private struct FooterSubtitleView: View {
    var body: some View {
        Text("LIVE AUDIO • ZERO DISK RECORDING")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .tracking(1.0)
    }
}
