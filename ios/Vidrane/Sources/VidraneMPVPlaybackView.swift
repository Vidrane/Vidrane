#if canImport(MPVKit)
import AVFoundation
import Combine
import MPVKit
import SwiftUI
import UniformTypeIdentifiers

/// MPVKit's event loop invokes its delegate on the main thread.
/// Keep the delegate in a separate object to avoid accidentally
/// exposing a @MainActor-isolated method to the C event thread.
private final class MPVEventSink: MPVCoreDelegate {
    var receive: ((MPVEvent) -> Void)?

    func mpv(_ core: MPVCore, event: MPVEvent) {
        receive?(event)
    }
}

/// A real libmpv session, unlike the native AVPlayer presentation mode.
/// MPVKit's core owns the decoder and AVFoundation never decodes these frames.
@MainActor
final class VidraneMPVSession: ObservableObject {
    let core = MPVCore()
    let request: PlaybackRequest

    @Published private(set) var elapsed: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var isPaused = true
    @Published private(set) var isBuffering = false
    @Published private(set) var tracks: [MPVTrack] = []
    @Published var errorMessage: String?

    private var started = false
    private var playbackLoaded = false
    private var lastSaved = Date.distantPast
    private var tempSubtitle: URL?
    private let sink = MPVEventSink()

    init(request: PlaybackRequest) {
        self.request = request
    }

    func prepare() throws {
        guard !started else { return }
        try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try core.create()

        var configuration = MPVConfiguration()
        configuration.hwdec = "videotoolbox"
        // Vidrane owns resume state so switching decoders uses the same
        // watch-history data. Don't enable mpv's parallel watch-later store.
        configuration.resumePlaybackEnabled = false
        configuration.apply(to: core)
        sink.receive = { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handle(event)
            }
        }
        core.delegate = sink

        do {
            try core.initialize()
        } catch {
            core.destroy()
            throw error
        }
        started = true
        lastSaved = Date()
    }

    /// Called only after an MPVGLView successfully attaches its render
    /// context, never before mpv_initialize().
    func load() {
        guard started && !playbackLoaded else { return }
        playbackLoaded = true
        core.playbackSpeed = max(0.5, min(2.0, UserDefaults.standard.double(forKey: "playbackRate") == 0
            ? 1.0 : UserDefaults.standard.double(forKey: "playbackRate")))
        let source = request.url.isFileURL ? request.url.path : request.url.absoluteString
        core.loadFile(source)
    }

    private func handle(_ event: MPVEvent) {
        switch event {
        case .fileLoaded:
            errorMessage = nil
            tracks = core.trackList()
            if UserDefaults.standard.object(forKey: "resumePlayback") as? Bool ?? true,
               let checkpoint = WatchHistory.shared.checkpoint(for: request.url) {
                core.seek(to: checkpoint.seconds)
            }
            isBuffering = false
        case .endFile(let reason):
            // libmpv's MPV_END_FILE_REASON_ERROR is 4.
            if reason == 4 {
                errorMessage = "libmpv не смог открыть или декодировать этот файл."
            } else if reason == 0 {
                WatchHistory.shared.remove(url: request.url)
            }
        case .shutdown:
            isPaused = true
        case .playbackRestart:
            isBuffering = false
        default:
            break
        }
    }

    func tick() {
        guard started else { return }
        let current = core.timePosition ?? 0
        let length = core.duration ?? 0
        elapsed = current.isFinite && current >= 0 ? current : 0
        duration = length.isFinite && length > 0 ? length : 0
        isPaused = core.isPaused
        // mpv exposes demuxer-cache-state separately. This flag follows
        // actual playback pause state, not network connection activity.
        isBuffering = core.getPropertyBool("paused-for-cache") ?? false
        if Date().timeIntervalSince(lastSaved) >= 5 {
            savePosition()
        }
    }

    func togglePause() {
        core.cyclePause()
        isPaused = core.isPaused
    }

    func seek(to seconds: Double) {
        let target = max(0, duration > 0 ? min(duration, seconds) : seconds)
        core.seek(to: target)
        elapsed = target
    }

    func skip(_ seconds: Double) {
        seek(to: elapsed + seconds)
    }

    func setSpeed(_ value: Double) {
        let clamped = max(0.5, min(2, value))
        core.playbackSpeed = clamped
        UserDefaults.standard.set(clamped, forKey: "playbackRate")
    }

    func selectAudio(_ track: MPVTrack?) {
        core.selectAudioTrack(track?.id)
        tracks = core.trackList()
    }

    func selectSubtitle(_ track: MPVTrack?) {
        core.selectSubtitleTrack(track?.id)
        tracks = core.trackList()
    }

    func addSubtitle(url: URL) throws {
        let ext = url.pathExtension.lowercased()
        guard ["srt", "ass", "ssa", "vtt"].contains(ext) else {
            throw NSError(domain: "Vidrane", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Поддерживаются SRT, ASS, SSA и VTT."
            ])
        }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let copy = FileManager.default.temporaryDirectory
            .appendingPathComponent("vidrane-mpv-\(UUID().uuidString).\(ext)")
        try FileManager.default.copyItem(at: url, to: copy)
        if let old = tempSubtitle { try? FileManager.default.removeItem(at: old) }
        tempSubtitle = copy
        core.addSubtitleFile(copy.path)
        tracks = core.trackList()
    }

    private func savePosition() {
        guard started, duration >= 30 else { return }
        WatchHistory.shared.record(url: request.url, seconds: elapsed, duration: duration)
        lastSaved = Date()
    }

    func finish() {
        guard started else { return }
        tick()
        WatchHistory.shared.record(url: request.url, seconds: elapsed, duration: duration)
        core.stop()
        core.destroy()
        started = false
        playbackLoaded = false
        sink.receive = nil
        if let tempSubtitle {
            try? FileManager.default.removeItem(at: tempSubtitle)
            self.tempSubtitle = nil
        }
    }
}

/// SwiftUI renderer for the real EAGL/OpenGL ES libmpv video output.
/// The GPU render context must be detached before the libmpv core is freed.
private struct MPVRenderSurface: UIViewRepresentable {
    let session: VidraneMPVSession

    func makeCoordinator() -> VidraneMPVSession { session }

    func makeUIView(context: Context) -> UIView {
        do {
            try session.prepare()
            guard let video = MPVGLView(core: session.core) else {
                session.errorMessage = "OpenGL ES 3 недоступен на этом устройстве."
                return UIView()
            }
            video.backgroundColor = .black
            do {
                try video.attachRenderContext()
            } catch {
                session.errorMessage = "Ошибка рендеринга libmpv: \(error)"
                video.teardown()
                return UIView()
            }
            session.load()
            return video
        } catch {
            session.errorMessage = "Не удалось запустить libmpv: \(error)"
            return UIView()
        }
    }

    func updateUIView(_ view: UIView, context: Context) {}

    static func dismantleUIView(_ view: UIView, coordinator: VidraneMPVSession) {
        if let video = view as? MPVGLView {
            video.teardown()
        }
        // mpv_render_context_free MUST precede mpv_terminate_destroy.
        coordinator.finish()
    }
}

struct VidraneMPVPlaybackView: View {
    let request: PlaybackRequest
    let onUseNative: () -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var session: VidraneMPVSession
    @State private var showControls = true
    @State private var pickingSubtitle = false
    @State private var scrubbing = false
    @State private var previewTime = 0.0

    private let ticker = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()

    init(request: PlaybackRequest, onUseNative: @escaping () -> Void) {
        self.request = request
        self.onUseNative = onUseNative
        _session = StateObject(wrappedValue: VidraneMPVSession(request: request))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(request.title).lineLimit(1).font(.subheadline.weight(.medium))
                Spacer()
                Button("Apple / AVFoundation") { onUseNative() }
                    .font(.caption)
                Button("Готово") { dismiss() }
                    .foregroundStyle(VidraneStyle.accent)
            }
            .padding(12)

            ZStack {
                MPVRenderSurface(session: session)
                    .background(.black)
                    .contentShape(Rectangle())
                    .onTapGesture { showControls.toggle() }

                if session.isBuffering {
                    ProgressView()
                        .tint(.white)
                }
                if showControls {
                    VStack {
                        Spacer()
                        controls
                    }
                }
                if let error = session.errorMessage {
                    VStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle")
                        Text("Ошибка libmpv").font(.headline)
                        Text(error).font(.caption).multilineTextAlignment(.center)
                        Button("Попробовать AVFoundation") { onUseNative() }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding(20)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                    .padding()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(.black)
        .onReceive(ticker) { _ in session.tick() }
        .onDisappear {
            // The renderer is removed by SwiftUI as part of the same view
            // teardown, so don't destroy mpv while MPVGLView still exists.
            session.tick()
        }
        .fileImporter(isPresented: $pickingSubtitle, allowedContentTypes: [.item]) { result in
            switch result {
            case .success(let url):
                do { try session.addSubtitle(url: url) }
                catch { session.errorMessage = error.localizedDescription }
            case .failure(let error):
                session.errorMessage = error.localizedDescription
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 12) {
            HStack {
                Text(time(session.elapsed))
                Spacer()
                Text(time(session.duration))
            }
            .font(.caption.monospacedDigit())

            Slider(
                value: Binding(
                    get: { scrubbing ? previewTime : session.elapsed },
                    set: { previewTime = $0; scrubbing = true }
                ),
                in: 0...max(1, session.duration),
                onEditingChanged: { editing in
                    if !editing {
                        session.seek(to: previewTime)
                        scrubbing = false
                    }
                }
            )
            .tint(VidraneStyle.accent)
            .disabled(session.duration <= 0)

            HStack(spacing: 24) {
                Button { session.skip(-10) } label: {
                    Image(systemName: "gobackward.10")
                }
                Button { session.togglePause() } label: {
                    Image(systemName: session.isPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 29))
                }
                Button { session.skip(10) } label: {
                    Image(systemName: "goforward.10")
                }

                Menu {
                    ForEach([0.5, 1.0, 1.25, 1.5, 2.0], id: \.self) { rate in
                        Button(String(format: "%g×", rate)) {
                            session.setSpeed(rate)
                        }
                    }
                } label: {
                    Image(systemName: "speedometer")
                }

                Menu {
                    Section("Аудиодорожки") {
                        ForEach(session.tracks.filter { $0.type == .audio }) { track in
                            Button(track.title ?? track.lang ?? "Аудио \(track.id)") {
                                session.selectAudio(track)
                            }
                        }
                    }
                    Section("Субтитры") {
                        Button("Выключить субтитры") { session.selectSubtitle(nil) }
                        ForEach(session.tracks.filter { $0.type == .sub }) { track in
                            Button(track.title ?? track.lang ?? "Субтитры \(track.id)") {
                                session.selectSubtitle(track)
                            }
                        }
                        Button("Добавить файл субтитров…") { pickingSubtitle = true }
                    }
                } label: {
                    Image(systemName: "captions.bubble")
                }
            }
            .font(.title2)
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
        }
        .foregroundStyle(.white)
        .padding()
        .background {
            LinearGradient(
                colors: [.clear, .black.opacity(0.85)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private func time(_ seconds: Double) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "0:00" }
        let total = Int(min(seconds, Double(Int.max / 2)))
        return total >= 3600
            ? String(format: "%d:%02d:%02d", total / 3600, (total / 60) % 60, total % 60)
            : String(format: "%d:%02d", total / 60, total % 60)
    }
}
#endif
