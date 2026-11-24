use vidrane_core::{http_range, subtitles, webdav};

#[test]
fn dav_fixture_preserves_successful_properties() {
    let entries =
        webdav::parse_multistatus(include_str!("../../../tests/fixtures/dav_multistatus.xml"))
            .unwrap();
    assert_eq!(entries.len(), 2);
    assert!(entries[0].is_directory);
    assert_eq!(entries[1].display_name, "Episode & test");
    assert_eq!(entries[1].size, Some(200_000));
}

#[test]
fn range_fixtures_cover_resume_and_rejected_headers() {
    for (header, offset, expected) in [
        ("bytes 0-199999/200000", 0, Some(200_000)),
        ("bytes 65536-199999/200000", 65536, Some(200_000)),
        ("bytes 0-65535/200000", 65536, None),
        ("bytes */200000", 200000, None),
        ("bytes 0-199999/*", 0, None),
    ] {
        assert_eq!(http_range::verify_download_range(header, offset), expected);
    }
}

#[test]
fn generated_subtitles_are_readable() {
    let Some(root) = std::env::var_os("VIDRANE_FIXTURES") else {
        return;
    };
    let root = std::path::PathBuf::from(root);
    for name in ["sample.srt", "sample.vtt"] {
        let input = std::fs::read_to_string(root.join(name)).unwrap();
        let cues = subtitles::parse(&input);
        assert_eq!(cues.len(), 1);
        assert_eq!(cues[0].start_ms, 200);
        assert_eq!(cues[0].end_ms, 1500);
    }
}
