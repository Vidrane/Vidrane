//! Shared media primitives for Vidrane, independent of platform and UI.

pub mod playlists;
pub mod providers;
pub mod transfers;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u32)]
pub enum MediaKind {
    Unknown = 0,
    Video = 1,
    Audio = 2,
    Subtitle = 3,
    Playlist = 4,
    Image = 5,
}

impl MediaKind {
    pub fn from_filename(filename: &str) -> Self {
        let suffix = filename
            .rsplit('.')
            .next()
            .unwrap_or("")
            .to_ascii_lowercase();
        match suffix.as_str() {
            "mp4" | "m4v" | "mov" | "mkv" | "avi" | "webm" | "wmv" | "ts" | "m2ts" | "mpg"
            | "mpeg" | "flv" | "3gp" | "ogv" => Self::Video,
            "mp3" | "aac" | "m4a" | "flac" | "wav" | "ogg" | "opus" | "aiff" | "alac" | "wma"
            | "ape" => Self::Audio,
            "srt" | "ass" | "ssa" | "vtt" | "sub" | "sup" => Self::Subtitle,
            "m3u" | "m3u8" | "pls" | "xspf" => Self::Playlist,
            "jpg" | "jpeg" | "png" | "gif" | "webp" | "heic" | "avif" => Self::Image,
            _ => Self::Unknown,
        }
    }

    pub fn is_playable(self) -> bool {
        matches!(self, Self::Video | Self::Audio)
    }
}

/// A signing profile is a deployment choice, not a subscription.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SigningProfile {
    Personal,
    Developer,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Capability {
    LocalPlayback,
    NetworkPlayback,
    PictureInPicture,
    PushNotifications,
    ICloud,
    AppGroups,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Requirement {
    Available,
    PlatformCheck,
    EntitlementCheck,
}

/// Do not infer that a paid Apple Developer account automatically grants
/// entitlements. Platform bridges must verify permissions at runtime.
pub fn requirement(capability: Capability) -> Requirement {
    match capability {
        Capability::LocalPlayback | Capability::NetworkPlayback => Requirement::Available,
        Capability::PictureInPicture => Requirement::PlatformCheck,
        Capability::PushNotifications | Capability::ICloud | Capability::AppGroups => {
            Requirement::EntitlementCheck
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn extensions_are_case_insensitive() {
        assert_eq!(MediaKind::from_filename("MOVIE.MKV"), MediaKind::Video);
        assert_eq!(MediaKind::from_filename("track.FLAC"), MediaKind::Audio);
        assert_eq!(MediaKind::from_filename("ru.Ass"), MediaKind::Subtitle);
        assert_eq!(
            MediaKind::from_filename("playlist.M3U8"),
            MediaKind::Playlist
        );
        assert_eq!(MediaKind::from_filename("poster.webp"), MediaKind::Image);
        assert_eq!(MediaKind::from_filename("unknown"), MediaKind::Unknown);
    }
    #[test]
    fn signing_profile_never_creates_premium_features() {
        for _profile in [SigningProfile::Personal, SigningProfile::Developer] {
            assert_eq!(
                requirement(Capability::LocalPlayback),
                Requirement::Available
            );
            assert_eq!(
                requirement(Capability::PushNotifications),
                Requirement::EntitlementCheck
            );
        }
    }
}
