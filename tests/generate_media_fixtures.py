"""Generate original, small media fixtures with FFmpeg; no media downloads."""
import json
import pathlib
import subprocess
import sys

out = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "target/media-fixtures")
out.mkdir(parents=True, exist_ok=True)
srt = out / "sample.srt"
srt.write_text("1\n00:00:00,200 --> 00:00:01,500\nVidrane fixture\n", encoding="utf-8")
(out / "sample.vtt").write_text("WEBVTT\n\n00:00.200 --> 00:01.500\nVidrane fixture\n", encoding="utf-8")
(out / "sample.ass").write_text(
    "[Script Info]\nScriptType: v4.00+\nPlayResX: 160\nPlayResY: 90\n\n"
    "[V4+ Styles]\nFormat: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, "
    "OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, "
    "Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding\n"
    "Style: Default,Arial,14,&H00FFFFFF,&H000000FF,&H00000000,&H80000000,"
    "0,0,0,0,100,100,0,0,1,1,0,2,8,8,8,1\n\n"
    "[Events]\nFormat: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\n"
    "Dialogue: 0,0:00:00.20,0:00:01.50,Default,,0,0,0,,Vidrane ASS\n",
    encoding="utf-8",
)

def ffmpeg(*args):
    subprocess.run(["ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "error",
                    "-y", *map(str, args)], check=True)

video = ["-f", "lavfi", "-i", "testsrc2=size=160x90:rate=10:duration=2"]
tone = ["-f", "lavfi", "-i", "sine=frequency=440:duration=2:sample_rate=44100"]
tone2 = ["-f", "lavfi", "-i", "sine=frequency=660:duration=2:sample_rate=44100"]
ffmpeg(*video, *tone, "-c:v", "mpeg4", "-c:a", "aac", out / "sample.mp4")
ffmpeg(*video, *tone, *tone2, "-i", srt, "-i", out / "sample.ass",
       "-map", "0:v", "-map", "1:a", "-map", "2:a", "-map", "3:s", "-map", "4:s",
       "-c:v", "mpeg4", "-c:a", "aac", "-c:s:0", "srt", "-c:s:1", "ass",
       "-metadata:s:a:0", "language=eng", "-metadata:s:a:1", "language=jpn", out / "multitrack.mkv")
ffmpeg(*tone, "-c:a", "pcm_s16le", out / "sample.wav")
(out / "corrupt.mp4").write_bytes((out / "sample.mp4").read_bytes()[:32])
(out / "corrupt.mkv").write_bytes(b"not a matroska container\x00")

def types(path):
    result = subprocess.check_output(["ffprobe", "-v", "error", "-show_streams", "-of", "json", str(path)])
    return [s["codec_type"] for s in json.loads(result)["streams"]]

assert types(out / "sample.mp4") == ["video", "audio"]
assert types(out / "multitrack.mkv") == ["video", "audio", "audio", "subtitle", "subtitle"]
assert types(out / "sample.wav") == ["audio"]
for name in ("corrupt.mp4", "corrupt.mkv"):
    result = subprocess.run(["ffprobe", "-v", "error", str(out / name)], capture_output=True)
    assert result.returncode != 0, name
print("Generated and validated original MP4/MKV/WAV/SRT/VTT/ASS fixtures")
