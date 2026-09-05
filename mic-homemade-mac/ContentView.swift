import SwiftUI
import CoreAudio

/// Main UI Screen for mic-homemade-mac.
/// Follows modular, small-widget design with clear responsibility separation.
struct ContentView: View {
    @StateObject private var audio = AudioEngineManager()

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Header: App Title & Mode
                HeaderSection()

                // Device Selection: Input & Output Dropdowns
                DeviceSelectorSection(audio: audio)

                // Warning Banner if Bluetooth is selected as Input
                if audio.isBluetoothInputWarning {
                    BluetoothInputWarningView()
                }

                // Live Audio Level Meter
                if audio.isRunning {
                    AudioLevelMeterView(level: audio.audioLevel, isMuted: audio.isMuted)
                }

                // Mute Toggle & Gain Control
                AudioControlSection(audio: audio)

                // Karaoke Voice Effects (Reverb & Echo)
                VoiceEffectsSection(audio: audio)

                // Latency Buffer Frame Selector (32, 64, 128, 256)
                BufferSelectorSection(selectedBuffer: audio.bufferSize) { newBuffer in
                    audio.updateBufferSize(newBuffer)
                }

                // Error Display (if any)
                if let error = audio.errorMessage {
                    ErrorMessageView(message: error)
                }

                // Main START / STOP Action Button
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
        .frame(width: 440, height: 680)
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
                Text("Ultra-Low Latency Live Passthrough & Karaoke")
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

// MARK: - Live Audio Level Meter

private struct AudioLevelMeterView: View {
    let level: Float
    let isMuted: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(isMuted ? "LIVE INPUT LEVEL (MUTED)" : "LIVE INPUT LEVEL")
                    .font(.caption2)
                    .foregroundStyle(isMuted ? .red : .secondary)
                    .fontWeight(.semibold)
                Spacer()
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

// MARK: - Karaoke Voice Effects Section

private struct VoiceEffectsSection: View {
    @ObservedObject var audio: AudioEngineManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Label("VOICE MODE & EFFECTS", systemImage: "sparkles")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)
                Spacer()
                if audio.reverbMix > 0 || audio.echoMix > 0 {
                    Text("EFFECTS ACTIVE")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.green)
                }
            }

            // Quick Voice Mode Buttons Grid
            HStack(spacing: 6) {
                ForEach(VoiceMode.allCases) { mode in
                    Button {
                        audio.setVoiceMode(mode)
                    } label: {
                        Text(mode.rawValue)
                            .font(.caption)
                            .fontWeight(audio.voiceMode == mode && (audio.reverbMix > 0 || mode == .normal) ? .bold : .regular)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(
                                audio.voiceMode == mode && (audio.reverbMix > 0 || mode == .normal)
                                ? Color.accentColor
                                : Color(nsColor: .windowBackgroundColor)
                            )
                            .foregroundStyle(
                                audio.voiceMode == mode && (audio.reverbMix > 0 || mode == .normal)
                                ? Color.white
                                : Color.primary
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()

            // Fine-Tuning Controls (Reverb & Echo Sliders)
            // Reverb Intensity Slider
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Reverb Intensity:")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text("\(Int(audio.reverbMix))%")
                        .font(.caption2)
                        .monospacedDigit()
                        .bold()
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

            // Vocal Echo Slider
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Echo (Delay Repeat):")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(audio.echoMix))%")
                        .font(.caption2)
                        .monospacedDigit()
                        .bold()
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

// MARK: - Buffer Selector Section

private struct BufferSelectorSection: View {
    let selectedBuffer: UInt32
    let onSelect: (UInt32) -> Void

    private let options: [UInt32] = [32, 64, 128, 256]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("BUFFER SIZE (LATENCY)")
                    .font(.caption2)
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
