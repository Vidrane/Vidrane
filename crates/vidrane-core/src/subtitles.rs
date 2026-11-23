//! Pure Rust parser for UTF-8 SRT and WebVTT timed text.
//!
//! This deliberately handles *text* subtitles, not image-based subtitles,
//! ASS layout commands, embedded media tracks or proprietary codecs.
use serde::Serialize;

#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct SubtitleCue {
    pub start_ms: u64,
    pub end_ms: u64,
    pub text: String,
}

pub fn parse(input: &str) -> Vec<SubtitleCue> {
    let normalized = input
        .trim_start_matches('\u{feff}')
        .replace("\r\n", "\n")
        .replace('\r', "\n");
    let mut cues = Vec::new();
    for block in normalized.split("\n\n") {
        let lines: Vec<&str> = block.lines().map(str::trim_end).collect();
        let Some(first) = lines.iter().find(|line| !line.trim().is_empty()) else {
            continue;
        };
        let first = first.trim_start();
        if first == "WEBVTT" || first.starts_with("WEBVTT ")
            || first == "NOTE" || first.starts_with("NOTE ")
            || first == "STYLE" || first == "REGION"
        {
            continue;
        }
        let Some(time_line) = lines.iter().position(|line| line.contains("-->")) else {
            continue;
        };
        let Some((start, rest)) = lines[time_line].split_once("-->") else {
            continue;
        };
        let Some(end) = rest.split_whitespace().next() else {
            continue;
        };
        let (Some(start_ms), Some(end_ms)) = (parse_time(start.trim()), parse_time(end)) else {
            continue;
        };
        if end_ms <= start_ms {
            continue;
        }
        let text = lines[time_line + 1..]
            .iter()
            .map(|line| strip_markup(line.trim()))
            .collect::<Vec<_>>()
            .join("\n")
            .trim()
            .to_owned();
        if !text.is_empty() {
            cues.push(SubtitleCue {
                start_ms,
                end_ms,
                text,
            });
        }
    }
    cues.sort_by_key(|cue| (cue.start_ms, cue.end_ms));
    cues
}

/// SRT uses commas; VTT uses periods. Supports hh:mm:ss.mmm and mm:ss.mmm.
fn parse_time(raw: &str) -> Option<u64> {
    let raw = raw.replace(',', ".");
    let (whole, fraction) = raw.split_once('.')?;
    if fraction.is_empty() || fraction.len() > 3
        || !fraction.bytes().all(|byte| byte.is_ascii_digit())
    {
        return None;
    }
    let chunks: Vec<&str> = whole.split(':').collect();
    if !(2..=3).contains(&chunks.len())
        || chunks.iter().any(|part| part.is_empty()
            || !part.bytes().all(|byte| byte.is_ascii_digit()))
    {
        return None;
    }
    let (hours, minutes, seconds) = if chunks.len() == 3 {
        (chunks[0].parse::<u64>().ok()?,
         chunks[1].parse::<u64>().ok()?,
         chunks[2].parse::<u64>().ok()?)
    } else {
        (0, chunks[0].parse::<u64>().ok()?, chunks[1].parse::<u64>().ok()?)
    };
    if seconds >= 60 || (chunks.len() == 3 && minutes >= 60) {
        return None;
    }
    let fraction = fraction.parse::<u64>().ok()?
        * 10_u64.pow((3 - fraction.len()) as u32);
    hours.checked_mul(3_600_000)?
        .checked_add(minutes.checked_mul(60_000)?)?
        .checked_add(seconds.checked_mul(1_000)?)?
        .checked_add(fraction)
}

/// Remove simple SRT/VTT inline tags for safe plain-text overlay display.
/// Formatting, ruby markup and karaoke are beyond this initial parser.
fn strip_markup(input: &str) -> String {
    let mut output = String::new();
    let mut in_tag = false;
    for character in input.chars() {
        match character {
            '<' => in_tag = true,
            '>' if in_tag => in_tag = false,
            _ if !in_tag => output.push(character),
            _ => {}
        }
    }
    output
        .replace("&lt;", "<")
        .replace("&gt;", ">")
        .replace("&quot;", "\"")
        .replace("&#39;", "'")
        .replace("&nbsp;", " ")
        .replace("&amp;", "&")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_srt_with_bom_crlf_and_markup() {
        let data = "\u{feff}1\r\n00:00:01,230 --> 00:00:03,500\r\n<b>Hello &amp; welcome</b>\r\n\r\n2\r\n00:00:04,0 --> 00:00:05,20\r\nSecond\r\nline\r\n";
        let cues = parse(data);
        assert_eq!(cues.len(), 2);
        assert_eq!(cues[0], SubtitleCue {
            start_ms: 1230, end_ms: 3500, text: "Hello & welcome".to_string()
        });
        assert_eq!(cues[1].end_ms, 5020);
        assert_eq!(cues[1].text, "Second\nline");
    }

    #[test]
    fn parses_webvtt_cue_labels_and_settings() {
        let data = "WEBVTT\n\nNOTE Example\nignore this\n\nSpeaker\n00:00:10.200 --> 00:00:12.000 align:start position:10%\n<v Anna>Hi!</v>\n\n00:13.0 --> 00:14.0\nNext";
        let cues = parse(data);
        assert_eq!(cues.len(), 2);
        assert_eq!(cues[0].start_ms, 10200);
        assert_eq!(cues[0].text, "Hi!");
        assert_eq!(cues[1].start_ms, 13000);
    }

    #[test]
    fn rejects_malformed_cues_and_out_of_range_times() {
        let data = "00:01.000 --> 00:00.500\nWrong\n\n00:01:90.000 --> 00:02:00.000\nWrong\n\n00:01.000 --> 00:02.000\nOK";
        let cues = parse(data);
        assert_eq!(cues.len(), 1);
        assert_eq!(cues[0].text, "OK");
    }

    #[test]
    fn no_cues_from_empty_or_headers() {
        assert!(parse("").is_empty());
        assert!(parse("WEBVTT\n\nNOTE description").is_empty());
    }
}
