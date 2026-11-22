//! Stable C ABI consumed by native presentation layers.
use std::ffi::{c_char, CStr};
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
}
