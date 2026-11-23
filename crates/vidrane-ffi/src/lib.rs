//! Stable C ABI consumed by native presentation layers.
use std::ffi::{c_char, CStr, CString};
use vidrane_core::media_engine::{choose, BackendProbe, EnginePreference};
use vidrane_core::MediaKind;

#[no_mangle]
pub extern "C" fn vidrane_media_kind(filename: *const c_char) -> u32 {
    if filename.is_null() {
        return MediaKind::Unknown as u32;
    }
    // SAFETY: The caller supplies a valid NUL-terminated C string.
    let name = unsafe { CStr::from_ptr(filename) };
    MediaKind::from_filename(&name.to_string_lossy()) as u32
}

#[no_mangle]
pub extern "C" fn vidrane_api_version() -> u32 {
    1
}

/// The returned seconds are always 0 or a valid nonnegative position.
#[no_mangle]
pub extern "C" fn vidrane_resume_position(position: f64, duration: f64) -> f64 {
    vidrane_core::watch_history::resume_position(position, duration)
}

#[no_mangle]
pub extern "C" fn vidrane_playback_finished(position: f64, duration: f64) -> bool {
    vidrane_core::watch_history::finished(position, duration)
}

/// Parse up to 8 MiB of UTF-8 SRT/WebVTT and return a JSON array of cues.
/// A non-null result is owned by Rust and MUST be freed with
/// vidrane_subtitles_free_json. Invalid inputs return null.
///
/// # Safety
/// input must point to a readable contiguous region of len bytes.
#[no_mangle]
pub unsafe extern "C" fn vidrane_subtitles_parse_json(input: *const u8, len: usize) -> *mut c_char {
    const MAX_BYTES: usize = 8 * 1024 * 1024;
    if input.is_null() || len == 0 || len > MAX_BYTES {
        return std::ptr::null_mut();
    }
    let bytes = std::slice::from_raw_parts(input, len);
    let Ok(source) = std::str::from_utf8(bytes) else {
        return std::ptr::null_mut();
    };
    let cues = vidrane_core::subtitles::parse(source);
    let Ok(serialized) = serde_json::to_string(&cues) else {
        return std::ptr::null_mut();
    };
    CString::new(serialized)
        .map(CString::into_raw)
        .unwrap_or(std::ptr::null_mut())
}

/// # Safety
/// ptr must be null or a pointer returned by vidrane_subtitles_parse_json
/// which has not already been freed.
#[no_mangle]
pub unsafe extern "C" fn vidrane_subtitles_free_json(ptr: *mut c_char) {
    if !ptr.is_null() {
        drop(CString::from_raw(ptr));
    }
}

/// Query shared backend selection. Engine IDs: 0=none, 1=native, 2=libmpv.
/// Preference: 0=automatic, 1=native-only, 2=libmpv-only.
/// The host MUST supply truthful runtime availability probes.
#[no_mangle]
pub extern "C" fn vidrane_choose_decoder(
    preference: u8,
    native_ready: bool,
    libmpv_ready: bool,
) -> u8 {
    let preference = match preference {
        0 => EnginePreference::Automatic,
        1 => EnginePreference::NativeOnly,
        2 => EnginePreference::LibmpvOnly,
        _ => return 0,
    };
    choose(
        preference,
        BackendProbe {
            native_ready,
            libmpv_ready,
        },
    ) as u8
}

/// Decode UTF-8 WebDAV XML into JSON. Caller must free the returned string.
///
/// # Safety
/// input points to a valid region of len bytes.
#[no_mangle]
pub unsafe extern "C" fn vidrane_webdav_parse_json(input: *const u8, len: usize) -> *mut c_char {
    if input.is_null() || len == 0 || len > 8 * 1024 * 1024 {
        return std::ptr::null_mut();
    }
    let bytes = std::slice::from_raw_parts(input, len);
    let Ok(xml) = std::str::from_utf8(bytes) else {
        return std::ptr::null_mut();
    };
    let Ok(entries) = vidrane_core::webdav::parse_multistatus(xml) else {
        return std::ptr::null_mut();
    };
    let Ok(json) = serde_json::to_string(&entries) else {
        return std::ptr::null_mut();
    };
    CString::new(json)
        .map(CString::into_raw)
        .unwrap_or(std::ptr::null_mut())
}

/// # Safety
/// ptr was returned by vidrane_webdav_parse_json and has not been freed.
#[no_mangle]
pub unsafe extern "C" fn vidrane_webdav_free_json(ptr: *mut c_char) {
    if !ptr.is_null() {
        drop(CString::from_raw(ptr));
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::ffi::CString;
    #[test]
    fn ffi_inputs() {
        let name = CString::new("movie.MP4").unwrap();
        assert_eq!(vidrane_media_kind(name.as_ptr()), 1);
        assert_eq!(vidrane_media_kind(std::ptr::null()), 0);
        assert_eq!(vidrane_api_version(), 1);
    }

    #[test]
    fn subtitle_ffi_roundtrip_and_deallocation() {
        let input = b"1\n00:00:01,000 --> 00:00:02,500\nHello\n";
        let result = unsafe { vidrane_subtitles_parse_json(input.as_ptr(), input.len()) };
        assert!(!result.is_null());
        let json = unsafe { CStr::from_ptr(result) }
            .to_str()
            .expect("valid UTF-8 JSON");
        assert!(json.contains("\"text\":\"Hello\""));
        unsafe { vidrane_subtitles_free_json(result) };
        assert!(unsafe { vidrane_subtitles_parse_json(std::ptr::null(), 10) }.is_null());
        assert_eq!(vidrane_choose_decoder(0, true, false), 1);
        assert_eq!(vidrane_choose_decoder(2, true, false), 0);
        assert_eq!(vidrane_choose_decoder(0, false, true), 2);
    }
}
