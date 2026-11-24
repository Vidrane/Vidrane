//! Strict HTTP Content-Range validation for bounded remote media reads.
//!
//! A server claiming success but returning a different offset could silently
//! corrupt a media stream. We reject truncated, wildcard and mismatched ranges.

/// Return total resource size if this header exactly describes the requested
/// inclusive byte range. Passing expected_total = None is for the one-byte
/// preflight probe that discovers file size.
pub fn verify_content_range(
    header: &str,
    expected_start: u64,
    expected_end: u64,
    expected_total: Option<u64>,
) -> Option<u64> {
    if header.len() > 128 || header.contains(['\r', '\n']) || expected_end < expected_start {
        return None;
    }
    let mut pieces = header.split_whitespace();
    if !pieces.next()?.eq_ignore_ascii_case("bytes") {
        return None;
    }
    let value = pieces.next()?;
    if pieces.next().is_some() {
        return None;
    }
    let (range, total) = value.split_once('/')?;
    if total.contains('/') {
        return None;
    }
    let total = decimal(total)?;
    let (start, end) = range.split_once('-')?;
    if start.contains('-') || end.contains('-') {
        return None;
    }
    let start = decimal(start)?;
    let end = decimal(end)?;
    if total == 0
        || start != expected_start
        || end != expected_end
        || end < start
        || end >= total
        || expected_total.is_some_and(|size| size != total)
    {
        return None;
    }
    Some(total)
}

fn decimal(value: &str) -> Option<u64> {
    if value.is_empty() || !value.bytes().all(|byte| byte.is_ascii_digit()) {
        return None;
    }
    value.parse().ok()
}

/// Validate a 206 response to an open-ended bytes=offset- request.
/// A complete-object download must end at total - 1; a shorter response
/// is not treated as a complete object. No signed or wildcard lengths.
pub fn verify_download_range(header: &str, offset: u64) -> Option<u64> {
    if header.len() > 128 {
        return None;
    }
    let (_, total) = header.split_once('/')?;
    let total = decimal(total)?;
    let end = total.checked_sub(1)?;
    verify_content_range(header, offset, end, Some(total))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn open_ended_download_requires_the_remaining_object() {
        assert_eq!(verify_download_range("bytes 100-899/900", 100), Some(900));
        assert_eq!(verify_download_range("bytes 100-199/900", 100), None);
        assert_eq!(verify_download_range("bytes 99-899/900", 100), None);
        assert_eq!(verify_download_range("bytes +100-899/900", 100), None);
        assert_eq!(verify_download_range("bytes 100-899/900\r\n", 100), None);
        assert_eq!(verify_download_range("bytes 0-0/0", 0), None);
    }

    #[test]
    fn accepts_precise_partial_content() {
        assert_eq!(verify_content_range("bytes 0-0/900", 0, 0, None), Some(900));
        assert_eq!(
            verify_content_range("bytes 100-199/900", 100, 199, Some(900)),
            Some(900)
        );
        assert_eq!(verify_content_range("BYTES 0-0/1", 0, 0, None), Some(1));
    }

    #[test]
    fn rejects_corrupt_and_mismatched_ranges() {
        for bad in [
            "bytes 0-899/*",
            "bytes 0-899/900/evil",
            "bytes 0-899/100",
            "bytes -1-0/900",
            "bytes 0-0/0",
            "bytes 0-0/900 extra",
            "items 0-0/900",
            "bytes 0-1/900",
            "bytes 0-0/901",
            "bytes 0-0/900\r\nInjected: header",
        ] {
            assert_eq!(
                verify_content_range(bad, 0, 0, Some(900)),
                None,
                "incorrectly accepted: {bad}"
            );
        }
    }

    #[test]
    fn rejects_integer_overflow_and_invalid_total() {
        assert_eq!(
            verify_content_range("bytes 0-0/18446744073709551616", 0, 0, None),
            None
        );
        assert_eq!(verify_content_range("bytes 5-6/6", 5, 6, None), None);
        assert_eq!(verify_content_range("bytes 2-1/5", 2, 1, None), None);
    }
}
