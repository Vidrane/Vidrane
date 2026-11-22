import SwiftUI
import AVKit
import Combine

struct PlaybackView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("keepScreenOn") private var keepScreenOn = true
    @AppStorage("playbackRate") private var playbackRate = 1.0
    @AppStorage("playerPresentation") private var playerPresentation = PlayerPresentation.apple.rawValue

    let request: PlaybackRequest

    // The same AVPlayer instance is retained when the interface changes,
    // preserving the stream, timestamp and current play/pause state.
    @State private var player = AVPlayer()
    @State private var selectedPresentation: PlayerPresentation = .apple
    @State private var elapsed = 0.0
    @State private var duration = 0.0
    @State private var scrubbing = false
    @State private var previewTime = 0.0
    @State private var playing = false
    @State private var showingControls = true

    private let progressTicker = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            header

            Group {
                switch selectedPresentation {
                case .apple:
                    SystemPlayer(player: player)
                case .vidrane:
                    customPlayer
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(.black)
        .onAppear(perform: start)
        .onReceive(progressTicker) { _ in
            updateProgress()
        }
        .onDisappear(perform: stop)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text(request.title)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Menu {
                ForEach(PlayerPresentation.allCases) { option in
                    Button {
                        selectedPresentation = option
                        playerPresentation = option.rawValue
                        showingControls = true
                    } label: {
                        if selectedPresentation == option {
                            Label(option.title, systemImage: "checkmark")
                        } else {
                            Text(option.title)
                        }
                    }
                }
            } label: {
                Label("Плеер", systemImage: "rectangle.on.rectangle")
                    .font(.subheadline)
            }
            .accessibilityLabel("Выбрать интерфейс плеера")

            Button("Готово") { dismiss() }
                .foregroundStyle(VidraneStyle.accent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.black)
    }

    private var customPlayer: some View {
        ZStack {
            VidraneVideoSurface(player: player)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        showingControls.toggle()
                    }
                }

            if showingControls {
                VStack {
                    Spacer()
                    customControls
                }
                .transition(.opacity)
            }
        }
        .background(.black)
        .accessibilityIdentifier("vidrane-custom-player")
    }

    private var customControls: some View {
        VStack(spacing: 14) {
            HStack {
                Text(formattedTime(scrubbing ? previewTime : elapsed))
                    .monospacedDigit()
                Spacer()
                Text(duration > 0 ? formattedTime(duration) : "—:—")
                    .monospacedDigit()
            }
            .font(.caption)

            Slider(
                value: Binding(
                    get: { scrubbing ? previewTime : elapsed },
                    set: {
                        previewTime = $0
                        scrubbing = true
                    }
                ),
                in: 0...max(duration, 1),
                onEditingChanged: { editing in
                    if !editing {
                        seek(to: previewTime)
                        scrubbing = false
                    }
                }
            )
            .tint(VidraneStyle.accent)
            .disabled(duration <= 0)
            .accessibilityLabel("Позиция воспроизведения")

            HStack(spacing: 28) {
                Button { skip(seconds: -10) } label: {
                    Image(systemName: "gobackward.10")
                }
                .accessibilityLabel("Назад на 10 секунд")

                Button { togglePlaying() } label: {
                    Image(systemName: playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 30))
                }
                .accessibilityLabel(playing ? "Пауза" : "Воспроизвести")

                Button { skip(seconds: 10) } label: {
                    Image(systemName: "goforward.10")
                }
                .accessibilityLabel("Вперёд на 10 секунд")

                Menu {
                    ForEach([0.5, 1.0, 1.25, 1.5, 2.0], id: \.self) { speed in
                        Button {
                            playbackRate = speed
                            if playing {
                                player.rate = Float(speed)
                            }
                        } label: {
                            Text(String(format: "%g×", speed))
                        }
                    }
                } label: {
                    Text(String(format: "%g×", playbackRate))
                        .font(.footnote.monospacedDigit())
                }
                .accessibilityLabel("Скорость воспроизведения")
            }
            .font(.title2)
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
        }
        .foregroundStyle(.white)
        .padding(18)
        .background {
            LinearGradient(
                colors: [.clear, .black.opacity(0.85)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private func start() {
        selectedPresentation = PlayerPresentation(rawValue: playerPresentation) ?? .apple
        player.replaceCurrentItem(with: AVPlayerItem(url: request.url))
        player.play()
        if playbackRate != 1 { player.rate = Float(playbackRate) }
        UIApplication.shared.isIdleTimerDisabled = keepScreenOn
        updateProgress()
    }

    private func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        UIApplication.shared.isIdleTimerDisabled = false
    }

    private func updateProgress() {
        let current = player.currentTime().seconds
        if current.isFinite && current >= 0 && !scrubbing {
            elapsed = current
        }
        let length = player.currentItem?.duration.seconds ?? .nan
        duration = length.isFinite && length > 0 ? length : 0
        playing = player.timeControlStatus == .playing
    }

    private func togglePlaying() {
        if player.timeControlStatus == .playing {
            player.pause()
        } else {
            player.play()
            player.rate = Float(playbackRate)
        }
        updateProgress()
    }

    private func skip(seconds: Double) {
        seek(to: elapsed + seconds)
    }

    private func seek(to seconds: Double) {
        let bounded = max(0, duration > 0 ? min(duration, seconds) : seconds)
        player.seek(to: CMTime(seconds: bounded, preferredTimescale: 600))
        elapsed = bounded
    }

    private func formattedTime(_ seconds: Double) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "0:00" }
        let value = Int(min(seconds, Double(Int.max / 2)))
        let hours = value / 3600
        let minutes = (value % 3600) / 60
        let remainder = value % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainder)
        }
        return String(format: "%d:%02d", minutes, remainder)
    }
}

struct SystemPlayer: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = true
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player { controller.player = player }
    }
}
