#include "VidraneBridge.h"
#include <assert.h>
#include <math.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>

int main(void) {
    assert(vidrane_api_version() == 1);
    assert(vidrane_media_kind("movie.MKV") == 1);
    assert(vidrane_media_kind("mp4") == 0);
    assert(vidrane_media_kind(NULL) == 0);
    assert(vidrane_resume_position(60, 300) == 60);
    assert(vidrane_resume_position(NAN, 300) == 0);
    assert(vidrane_playback_finished(299, 300));
    assert(!vidrane_playback_finished(0, 0));
    assert(vidrane_choose_decoder(0, false, true) == 2);
    assert(vidrane_choose_decoder(255, true, true) == 0);
    assert(vidrane_prefers_libmpv_extension("MKV"));
    assert(!vidrane_prefers_libmpv_extension("mp4"));
    assert(!vidrane_prefers_libmpv_extension(NULL));
    assert(vidrane_content_range_total("bytes 0-0/900", 0, 0, 0) == 900);
    assert(vidrane_content_range_total("bytes 0-1/900", 0, 0, 0) == 0);
    assert(vidrane_content_range_total(NULL, 0, 0, 0) == 0);
    assert(vidrane_download_range_total("bytes 100-899/900", 100) == 900);
    assert(vidrane_download_range_total("bytes 100-199/900", 100) == 0);
    const char srt[] = "1\n00:00:01,000 --> 00:00:02,500\nHello\n";
    char *json = vidrane_subtitles_parse_json((const uint8_t *)srt, strlen(srt));
    assert(json && strstr(json, "Hello") && strstr(json, "2500"));
    vidrane_subtitles_free_json(json);
    vidrane_subtitles_free_json(NULL);
    assert(!vidrane_subtitles_parse_json(NULL, 1));
    const char dav[] = "<multistatus xmlns=\"DAV:\"><response><href>/test.mkv</href>"
        "<propstat><prop><getcontentlength>12</getcontentlength></prop>"
        "<status>HTTP/1.1 200 OK</status></propstat></response></multistatus>";
    json = vidrane_webdav_parse_json((const uint8_t *)dav, strlen(dav));
    assert(json && strstr(json, "/test.mkv") && strstr(json, "12"));
    vidrane_webdav_free_json(json);
    vidrane_webdav_free_json(NULL);
    assert(!vidrane_webdav_parse_json(NULL, 1));
    puts("Vidrane native C ABI checks passed");
    return 0;
}
