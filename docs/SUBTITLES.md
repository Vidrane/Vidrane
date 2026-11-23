# External subtitles on iOS

Vidrane can parse UTF-8 SRT and WebVTT in the shared Rust core and render
the text over playback.

How to use:
1. Open a local video.
2. Vidrane looks beside it for a matching subtitle file: Movie.srt,
   Movie.vtt or Movie.ru.srt.
3. Alternatively use the in-player tracks and subtitles menu, then choose
   an external file with the Apple Files picker.
4. Turn external subtitles on or off in the same menu.
5. Choose font size and caption background in Settings.

The app does not silently copy a manually selected subtitle file into its
sandbox. An imported sidecar stored alongside the video can be found at
the next playback session.

Limitations:
- UTF-8 plain-text SRT/VTT only. No advanced ASS/SSA styles, PGS,
  bitmap subtitles, karaoke animation or non-UTF-8 legacy encodings.
- External captions are an overlay in the app, not embedded in the video.
  They do not appear inside the system Picture-in-Picture window or AirPlay.
- Embedded subtitle tracks exposed by AVFoundation are independent of this
  external-text feature.
- The parser refuses empty or larger-than-8-MiB subtitle inputs.
- No automatic external subtitle downloads for remote streams.
- Physical iPhone tests are still needed for timing, layout and rotation.

Rust unit tests cover SRT/VTT, Unicode BOM, CRLF, timing and malformed cues.
The Swift bridge uses owned JSON and calls the matching Rust free function.

Subtitle timing offset: Settings has an adjustment from -10 to +10 seconds, in half-second steps. A positive offset displays captions later; the in-player subtitles menu also has earlier/later and reset actions. The delay is persisted locally.
