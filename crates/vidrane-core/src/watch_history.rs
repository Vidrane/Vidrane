//! Platform-neutral policy for saving/restoring interrupted playback.
//! The host app owns persistence and user preferences.

/// Returns a safe resume time, or 0 if the playback position should be
/// ignored. Ignore very short clips, their opening seconds and almost-finished
/// files, so old positions never trap users at the closing credits.
pub fn resume_position(position: f64, duration: f64) -> f64 {
    if !position.is_finite() || !duration.is_finite() {
        return 0.0;
    }
    if duration < 30.0 || position < 5.0 || position >= duration {
        return 0.0;
    }
    if duration - position <= 15.0 || position / duration >= 0.95 {
        return 0.0;
    }
    position
}

/// Whether the saved checkpoint should be discarded after a file was watched
/// to its end. Keeping this separate avoids erasing valid history before the
/// media item has loaded its duration.
pub fn finished(position: f64, duration: f64) -> bool {
    position.is_finite()
        && duration.is_finite()
        && duration > 0.0
        && position >= 0.0
        && (duration - position <= 15.0 || position / duration >= 0.95)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn resumes_only_when_useful() {
        assert_eq!(resume_position(120.0, 300.0), 120.0);
        assert_eq!(resume_position(4.0, 300.0), 0.0);
        assert_eq!(resume_position(12.0, 20.0), 0.0);
        assert_eq!(resume_position(299.0, 300.0), 0.0);
        assert_eq!(resume_position(f64::NAN, 300.0), 0.0);
        assert_eq!(resume_position(120.0, f64::INFINITY), 0.0);
        assert_eq!(resume_position(-10.0, 300.0), 0.0);
        assert_eq!(resume_position(350.0, 300.0), 0.0);
    }

    #[test]
    fn completed_is_not_unknown() {
        assert!(finished(298.0, 300.0));
        assert!(!finished(120.0, 300.0));
        assert!(!finished(0.0, 0.0));
        assert!(!finished(f64::NAN, 300.0));
    }
}
