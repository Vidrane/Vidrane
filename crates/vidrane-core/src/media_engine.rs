//! Shared policy for selecting a real installed playback backend.
//! This does not install, bundle or emulate libmpv/FFmpeg.

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EnginePreference {
    Automatic,
    NativeOnly,
    LibmpvOnly,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u8)]
pub enum Decoder {
    Unavailable = 0,
    Native = 1,
    Libmpv = 2,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct BackendProbe {
    /// Is a native decoder instantiated and capable of the requested asset?
    pub native_ready: bool,
    /// Is a real libmpv decoder installed and capable of the requested asset?
    pub libmpv_ready: bool,
}

/// In automatic mode prefer native hardware decoding where available and
/// explicitly fall back to a *working* libmpv adapter where available.
/// Never report an uninstalled backend as ready.
pub fn choose(preference: EnginePreference, available: BackendProbe) -> Decoder {
    match preference {
        EnginePreference::Automatic => {
            if available.native_ready {
                Decoder::Native
            } else if available.libmpv_ready {
                Decoder::Libmpv
            } else {
                Decoder::Unavailable
            }
        }
        EnginePreference::NativeOnly if available.native_ready => Decoder::Native,
        EnginePreference::LibmpvOnly if available.libmpv_ready => Decoder::Libmpv,
        _ => Decoder::Unavailable,
    }
}

/// Initial routing hint only: the platform must still probe actual codecs.
/// Accept an extension, not a URL; caller decides which sources can use it.
pub fn prefers_libmpv_extension(extension: &str) -> bool {
    const CANDIDATES: &[&str] = &[
        "mkv", "avi", "webm", "flv", "wmv", "ts", "m2ts", "ogg", "opus", "flac", "ape", "mka", "ogv",
    ];
    CANDIDATES
        .iter()
        .any(|item| item.eq_ignore_ascii_case(extension))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn extension_hint_is_not_a_codec_probe() {
        assert!(prefers_libmpv_extension("MKV"));
        assert!(prefers_libmpv_extension("mka"));
        assert!(!prefers_libmpv_extension("mp4"));
        assert!(!prefers_libmpv_extension("https://example.org/movie.mkv"));
    }

    #[test]
    fn automatic_prefers_native_and_falls_back() {
        let both = BackendProbe {
            native_ready: true,
            libmpv_ready: true,
        };
        assert_eq!(choose(EnginePreference::Automatic, both), Decoder::Native);
        let only_mpv = BackendProbe {
            native_ready: false,
            libmpv_ready: true,
        };
        assert_eq!(
            choose(EnginePreference::Automatic, only_mpv),
            Decoder::Libmpv
        );
    }

    #[test]
    fn never_selects_uninstalled_decoder() {
        let native_only = BackendProbe {
            native_ready: true,
            libmpv_ready: false,
        };
        assert_eq!(
            choose(EnginePreference::LibmpvOnly, native_only),
            Decoder::Unavailable
        );
        assert_eq!(
            choose(EnginePreference::Automatic, native_only),
            Decoder::Native
        );
        let none = BackendProbe {
            native_ready: false,
            libmpv_ready: false,
        };
        assert_eq!(
            choose(EnginePreference::Automatic, none),
            Decoder::Unavailable
        );
    }
}
