import SwiftUI
import AVKit
import Combine
import UniformTypeIdentifiers

struct PlaybackView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("keepScreenOn") private var keepScreenOn = true
    @AppStorage("playbackRate") private var playbackRate = 1.0
    @AppStorage("playerPresentation") private var playerPresentation = PlayerPresentation.vidrane.rawValue
    @AppStorage("resumePlayback") private var resumePlayback = true
    @AppStorage("videoScaling") private var videoScaling = VideoScaling.fit.rawValue
    @AppStorage("subtitleFontSize") private var subtitleFontSize = 24.0
    @AppStorage("subtitleBackground") private var subtitleBackground = true
    @StateObject private var externalSubtitles = ExternalSubtitles()
    @State private var importingExternalSubtitles = false
    @ObservedObject private var watchHistory = WatchHistory.shared

    let request: PlaybackRequest

    // The same AVPlayer instance is retained when the interface changes,
    // preserving the stream, timestamp and current play/pause state.
    @State private var player = AVPlayer()
    @State private var pictureInPicture = VidranePictureInPicture()
    @State private var selectedPresentation: PlayerPresentation = .vidrane
    @State private var elapsed = 0.0
    @State private var duration = 0.0
    @State private var scrubbing = false
    @State private var previewTime = 0.0
    @State private var playing = false
    @State private var showingControls = true
    @State private var playbackError: String?
    @State private var pendingResume = 0.0
    @State private var pendingDuration = 0.0
    @State private var waitingToResume = false
    @State private var seekingToResume = false
    @State private var lastCheckpointAt: Date = .distantPast
    @State private var audioGroup: AVMediaSelectionGroup?
    @State private var subtitleGroup: AVMediaSelectionGroup?

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
            .overlay {
                if let playbackError {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 30))
                        Text("Не удалось воспроизвести файл")
                            .font(.headline)
                        Text(playbackError)
                            .font(.caption)
                            .multilineTextAlignment(.center)
                        Text("Vidrane пока использует AVFoundation. Дополнительные декодеры FFmpeg/libmpv ещё не подключены.")
                            .font(.caption2)
                            .multilineTextAlignment(.center)
                    }
                    .padding(20)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                    .padding(22)
                    .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .bottom) {
                if let subtitle = externalSubtitles.cue(at: elapsed) {
                    Text(subtitle)
                        .font(.system(size: subtitleFontSize, weight: .medium))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                        .shadow(color: .black, radius: 3)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background {
                            if subtitleBackground {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.black.opacity(0.72))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 12)
                        .padding(.bottom, selectedPresentation == .vidrane && showingControls ? 145 : 80)
                        .allowsHitTesting(false)
                        .accessibilityLabel(subtitle)
                }
            }
        }
        .background(.black)
        .onAppear(perform: start)
        .onReceive(progressTicker) { _ in
            updateProgress()
        }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { message in
            guard let ended = message.object as? AVPlayerItem,
                  ended === player.currentItem else { return }
            watchHistory.remove(url: request.url)
        }
        .onDisappear(perform: stop)
        .fileImporter(
            isPresented: $importingExternalSubtitles,
            allowedContentTypes: [.item]
        ) { result in
            switch result {
            case .success(let url):
                _ = externalSubtitles.load(url: url)
            case .failure(let error):
                externalSubtitles.errorMessage = error.localizedDescription
            }
        }
        .alert(
            "Внешние субтитры",
            isPresented: Binding(
                get: { externalSubtitles.errorMessage != nil },
                set: { if !$0 { externalSubtitles.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                externalSubtitles.errorMessage = nil
            }
        } message: {
            Text(externalSubtitles.errorMessage ?? "")
        }
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
                        // Session-only switch; default is changed in Settings.
                        selectedPresentation = option
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

            Button {
                watchHistory.remove(url: request.url)
                seek(to: 0)
            } label: {
                Image(systemName: "arrow.counterclockwise")
            }
            .accessibilityLabel("Начать сначала")

            Button("Готово") { dismiss() }
                .foregroundStyle(VidraneStyle.accent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.black)
    }

    private var customPlayer: some View {
        ZStack {
            GeometryReader { dimensions in
                VidraneVideoSurface(
                    player: player,
                    gravity: (VideoScaling(rawValue: videoScaling) ?? .fit).gravity,
                    pictureInPicture: pictureInPicture
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    SpatialTapGesture(count: 2)
                        .exclusively(before: TapGesture())
                        .onEnded { gesture in
                            switch gesture {
                            case .first(let tap):
                                skip(seconds: tap.location.x < dimensions.size.width / 2 ? -10 : 10)
                            case .second:
                                withAnimation(.easeInOut(duration: 0.18)) {
                                    showingControls.toggle()
                                }
                            }
                        }
                )
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

            HStack(spacing: 14) {
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

                if pictureInPicture.supported {
                    Button {
                        pictureInPicture.start()
                    } label: {
                        Image(systemName: "pip.enter")
                    }
                    .disabled(!pictureInPicture.possible)
                    .accessibilityLabel("Картинка в картинке")
                }

                mediaTracksMenu

                Menu {
                    ForEach(VideoScaling.allCases) { scaling in
                        Button {
                            videoScaling = scaling.rawValue
                        } label: {
                            if videoScaling == scaling.rawValue {
                                Label(scaling.title, systemImage: "checkmark")
                            } else {
                                Text(scaling.title)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "aspectratio")
                }
                .accessibilityLabel("Масштаб видео")
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

    @ViewBuilder
    private var mediaTracksMenu: some View {
        Menu {
            Section("Аудиодорожка") {
                if let group = audioGroup {
                    ForEach(group.options.indices, id: \.self) { index in
                        let option = group.options[index]
                        Button {
                            selectTrack(option, in: group)
                        } label: {
                            if player.currentItem?.currentMediaSelection.selectedMediaOption(in: group) === option {
                                Label(option.displayName, systemImage: "checkmark")
                            } else {
                                Text(option.displayName)
                            }
                        }
                    }
                } else {
                    Text("Нет альтернативных дорожек")
                }
            }
            Section("Встроенные субтитры") {
                if let group = subtitleGroup {
                    Button {
                        selectTrack(nil, in: group)
                    } label: {
                        if player.currentItem?.currentMediaSelection.selectedMediaOption(in: group) == nil {
                            Label("Выключены", systemImage: "checkmark")
                        } else {
                            Text("Выключены")
                        }
                    }
                    ForEach(group.options.indices, id: \.self) { index in
                        let option = group.options[index]
                        Button {
                            selectTrack(option, in: group)
                        } label: {
                            if player.currentItem?.currentMediaSelection.selectedMediaOption(in: group) === option {
                                Label(option.displayName, systemImage: "checkmark")
                            } else {
                                Text(option.displayName)
                            }
                        }
                    }
                } else {
                    Text("Нет встроенных субтитров")
                }
            }
            Section("Внешние субтитры SRT / WebVTT") {
                Button {
                    importingExternalSubtitles = true
                } label: {
                    Label("Выбрать файл…", systemImage: "doc.text")
                }
                if let filename = externalSubtitles.filename {
                    Button {
                        externalSubtitles.enabled.toggle()
                    } label: {
                        Label(
                            externalSubtitles.enabled ? "Показывать: \(filename)" : "Включить: \(filename)",
                            systemImage: externalSubtitles.enabled ? "checkmark.circle.fill" : "circle"
                        )
                    }
                    Button(role: .destructive) {
                        externalSubtitles.clear()
                    } label: {
                        Label("Отключить внешние", systemImage: "xmark.circle")
                    }
                } else {
                    Text("Не выбраны")
                }
            }
        } label: {
            Image(systemName: "captions.bubble")
        }
        .accessibilityLabel("Дорожки и субтитры")
    }

    private func selectTrack(
        _ option: AVMediaSelectionOption?,
        in group: AVMediaSelectionGroup
    ) {
        // Manual selection overrides the user's system language preferences
        // for this playback session only.
        player.appliesMediaSelectionCriteriaAutomatically = false
        player.currentItem?.select(option, in: group)
        if group === subtitleGroup && option != nil {
            externalSubtitles.enabled = false
        }
    }

    private func loadTracks(for item: AVPlayerItem) {
        audioGroup = nil
        subtitleGroup = nil
        Task { @MainActor in
            // Async loading is required for network/HLS assets; the player
            // may have changed while the selection groups are loading.
            let audio = try? await item.asset.loadMediaSelectionGroup(for: .audible)
            let subtitles = try? await item.asset.loadMediaSelectionGroup(for: .legible)
            guard player.currentItem === item else { return }
            audioGroup = audio
            subtitleGroup = subtitles
        }
    }

    private func start() {
        selectedPresentation = PlayerPresentation(rawValue: playerPresentation) ?? .vidrane
        externalSubtitles.loadSidecar(for: request.url)
        let saved = resumePlayback ? watchHistory.checkpoint(for: request.url) : nil
        pendingResume = saved?.seconds ?? 0
        pendingDuration = saved?.duration ?? 0
        waitingToResume = pendingResume > 0
        seekingToResume = false
        lastCheckpointAt = Date()
        playbackError = nil
        let item = AVPlayerItem(url: request.url)
        player.replaceCurrentItem(with: item)
        loadTracks(for: item)
        player.play()
        if playbackRate != 1 { player.rate = Float(playbackRate) }
        UIApplication.shared.isIdleTimerDisabled = keepScreenOn
        updateProgress()
    }

    private func stop() {
        saveCheckpoint()
        player.pause()
        player.replaceCurrentItem(with: nil)
        UIApplication.shared.isIdleTimerDisabled = false
    }

    private func saveCheckpoint() {
        guard !waitingToResume, !seekingToResume,
              let item = player.currentItem, item.status == .readyToPlay else { return }
        watchHistory.record(
            url: request.url,
            seconds: player.currentTime().seconds,
            duration: item.duration.seconds
        )
        lastCheckpointAt = Date()
    }

    private func updateProgress() {
        guard let item = player.currentItem else { return }
        if item.status == .failed || player.status == .failed {
            playbackError = item.error?.localizedDescription
                ?? player.error?.localizedDescription
                ?? "Формат, кодек или источник недоступен системному плееру."
            return
        }

        // Wait until the AVPlayerItem is ready before seeking. Never let the
        // initial 0:00 playback overwrite the previous saved checkpoint.
        if waitingToResume && !seekingToResume && item.status == .readyToPlay {
            let mediaDuration = item.duration.seconds
            let actualDuration = mediaDuration.isFinite ? mediaDuration : pendingDuration
            let target = vidrane_resume_position(pendingResume, actualDuration)
            waitingToResume = false
            if target > 0 {
                seekingToResume = true
                player.seek(
                    to: CMTime(seconds: target, preferredTimescale: 600),
                    toleranceBefore: .zero,
                    toleranceAfter: .zero
                ) { completed in
                    Task { @MainActor in
                        if completed { elapsed = target }
                        seekingToResume = false
                        lastCheckpointAt = Date()
                    }
                }
            }
        }

        let current = player.currentTime().seconds
        if current.isFinite && current >= 0 && !scrubbing && !seekingToResume {
            elapsed = current
        }
        let length = item.duration.seconds
        duration = length.isFinite && length > 0 ? length : 0
        playing = player.timeControlStatus == .playing

        if !waitingToResume && !seekingToResume &&
            Date().timeIntervalSince(lastCheckpointAt) >= 5 {
            saveCheckpoint()
        }
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
        if bounded < 5 {
            watchHistory.remove(url: request.url)
        }
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
