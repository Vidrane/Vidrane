import SwiftUI

// libmpv is mandatory in both main iOS signing configurations. This must
// be a build failure, not a silent fallback that ships AVFoundation-only.
#if !canImport(MPVKit)
#error("Main Vidrane iOS builds must link MPVKit/libmpv. Run ios/mpv/prepare.sh before generating the Xcode project.")
#endif

/// Decoder selection is independent of the appearance of playback controls.
enum DecoderPreference: String, CaseIterable, Identifiable {
    case automatic
    case avFoundation
    case libmpv

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: return "Автоматически"
        case .avFoundation: return "Apple AVFoundation"
        case .libmpv: return "libmpv / FFmpeg"
        }
    }
}

enum PlaybackDecoderAvailability {
    static var hasLibmpv: Bool {
        #if canImport(MPVKit)
        true
        #else
        false
        #endif
    }

    /// This is intentionally an extension-based starting choice, NOT a
    /// promise that a particular codec can be decoded. The native player's
    /// failure UI offers a real libmpv retry when linked.
    static func prefersLibmpv(for url: URL, preference: DecoderPreference) -> Bool {
        guard hasLibmpv else { return false }
        switch preference {
        case .avFoundation: return false
        case .libmpv: return true
        case .automatic:
            let mpvCandidates: Set<String> = [
                "mkv", "avi", "webm", "flv", "wmv", "ts", "m2ts",
                "ogg", "opus", "flac", "ape", "mka", "ogv"
            ]
            return url.isFileURL && mpvCandidates.contains(url.pathExtension.lowercased())
        }
    }
}

/// Retains a single media request while changing backend after an error.
/// This differs from changing the Vidrane/Apple presentation, which reuses
/// the same AVPlayer within PlaybackView.
struct PlaybackHostView: View {
    let request: PlaybackRequest
    @AppStorage("decoderPreference") private var storedPreference = DecoderPreference.automatic.rawValue
    @AppStorage("playerPresentation") private var playerPresentation = PlayerPresentation.vidrane.rawValue
    @State private var overrideLibmpv: Bool?

    private var libmpvSelected: Bool {
        // The authenticated DAV and SFTP streams are AVFoundation
        // resource-loader assets, not libmpv URLs.
        if request.remoteRelay != nil { return true }
        if request.webDAVStream != nil || request.sftpStream != nil {
            return false
        }
        if let overrideLibmpv { return overrideLibmpv }
        let pref = DecoderPreference(rawValue: storedPreference) ?? .automatic
        // Apple AVPlayerViewController can only wrap an AVPlayer. Automatic
        // routing respects that UI choice; explicit libmpv remains allowed
        // but uses Vidrane's custom mpv controls instead of Apple controls.
        if pref == .automatic && playerPresentation == PlayerPresentation.apple.rawValue {
            return false
        }
        return PlaybackDecoderAvailability.prefersLibmpv(for: request.url, preference: pref)
    }

    var body: some View {
        Group {
            #if canImport(MPVKit)
            if libmpvSelected {
                VidraneMPVPlaybackView(request: request) {
                    overrideLibmpv = false
                }
            } else {
                PlaybackView(
                    request: request,
                    onTryLibmpv: request.webDAVStream == nil &&
                        request.sftpStream == nil && request.remoteRelay == nil
                        ? { overrideLibmpv = true } : nil
                )
            }
            #else
            PlaybackView(request: request, onTryLibmpv: nil)
            #endif
        }
    }
}
