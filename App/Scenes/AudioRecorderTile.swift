import AppKit
import AVFAudio
import SwiftUI

/// Audio recorder tile — record/stop, live level meter, elapsed time, and the newest take with a
/// reveal in Finder. The mic runs only while a take runs (the no-polling discipline); a take is
/// finalised if the tile goes away mid-recording.
struct AudioRecorderTile: View {
    let env: TileEnv
    let width: CGFloat
    let height: CGFloat
    @StateObject private var model = WidgetRecorderModel()

    var body: some View {
        BandTile(env: env, kind: .timer, width: width, height: height, header: {
            HStack(spacing: 6) {
                Text("Recorder")
                Spacer()
                if model.isRecording {
                    Image(systemName: "circle.fill").font(.system(size: 7))
                        .foregroundColor(env.onAccent(.timer))
                }
            }
        }, content: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Button { model.toggle() } label: {
                        ZStack {
                            Circle().fill(env.accent(.timer))
                            if model.isRecording {
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(env.onAccent(.timer)).frame(width: 18, height: 18)
                            } else {
                                Image(systemName: "mic.fill").font(.system(size: 20, weight: .semibold))
                                    .foregroundColor(env.onAccent(.timer))
                            }
                        }
                        .frame(width: 50, height: 50)
                    }
                    .buttonStyle(.plain)
                    .help(model.isRecording ? Text("Stop") : Text("Record"))
                    .accessibilityLabel(model.isRecording ? Text("Stop") : Text("Record"))
                    Text(verbatim: model.elapsed)
                        .font(.system(size: 26, weight: .bold, design: .rounded)).monospacedDigit()
                        .foregroundColor(env.text)
                    Spacer(minLength: 0)
                }
                // Level meter: segmented bars light up from the recorder's average power.
                HStack(spacing: 3) {
                    ForEach(0..<22, id: \.self) { i in
                        Capsule()
                            .fill(i < Int(model.level * 22)
                                  ? Color(hue: 0.98 - Double(i) * 0.012, saturation: 0.85, brightness: 0.95)
                                  : env.text.opacity(0.12))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(height: 24)
                .accessibilityHidden(true)
                if let take = model.lastTake {
                    HStack(spacing: 6) {
                        Image(systemName: "waveform").font(.system(size: 11)).foregroundColor(env.secondary)
                        Text(verbatim: take.lastPathComponent).font(.system(size: 11))
                            .foregroundColor(env.secondary).lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 0)
                        Button { NSWorkspace.shared.activateFileViewerSelecting([take]) } label: {
                            Image(systemName: "folder")
                        }
                        .buttonStyle(.borderless).help(Text("Show in Finder"))
                    }
                }
            }
        })
        .onDisappear { model.stop() }
    }
}

/// Owns the mic take behind `AudioRecorderTile`: one recording at a time in
/// `~/Documents/Recordings`, level and elapsed fed by a timer that exists only while recording.
final class WidgetRecorderModel: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var elapsed = "0:00"
    @Published private(set) var level: CGFloat = 0
    @Published private(set) var lastTake: URL?

    private var recorder: AVAudioRecorder?
    private var ticker: Timer?

    func toggle() {
        if isRecording {
            stop()
        } else if AVAudioApplication.shared.recordPermission == .denied {
            // Denied can't re-prompt: send the only affordance where it can be flipped (rule 7).
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
        } else {
            AVAudioApplication.requestRecordPermission { [weak self] granted in
                DispatchQueue.main.async { if granted { self?.start() } }
            }
        }
    }

    /// Stops and finalises the file; safe to call when idle.
    func stop() {
        recorder?.stop()
        recorder = nil
        ticker?.invalidate()
        ticker = nil
        isRecording = false
        level = 0
    }

    private func start() {
        let dir = Self.recordingsDir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("Take \(Self.stamp()).m4a")
        let settings: [String: Any] = [AVFormatIDKey: Int(kAudioFormatMPEG4AAC), AVSampleRateKey: 44_100.0,
                                       AVNumberOfChannelsKey: 1, AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue]
        guard let rec = try? AVAudioRecorder(url: url, settings: settings), rec.record() else { return }
        rec.isMeteringEnabled = true
        recorder = rec
        lastTake = url
        elapsed = "0:00"
        level = 0
        isRecording = true
        ticker = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in self?.sample() }
    }

    private func sample() {
        guard let rec = recorder else { return }
        rec.updateMeters()
        let t = rec.currentTime
        elapsed = String(format: "%d:%02d", Int(t) / 60, Int(t) % 60)
        level = CGFloat(max(0, min(1, (rec.averagePower(forChannel: 0) + 60) / 60)))
    }

    private static var recordingsDir: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Recordings")
    }

    private static func stamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return f.string(from: Date())
    }
}
