#ifndef VIDRANE_BRIDGE_H
#define VIDRANE_BRIDGE_H
#include <stdint.h>
#include <stdbool.h>
uint32_t vidrane_media_kind(const char *filename);
uint32_t vidrane_api_version(void);
double vidrane_resume_position(double position, double duration);
bool vidrane_playback_finished(double position, double duration);
char *vidrane_subtitles_parse_json(const uint8_t *input, uintptr_t len);
void vidrane_subtitles_free_json(char *json);
uint8_t vidrane_choose_decoder(uint8_t preference, bool native_ready, bool libmpv_ready);
char *vidrane_webdav_parse_json(const uint8_t *input, uintptr_t len);
void vidrane_webdav_free_json(char *json);
uint64_t vidrane_content_range_total(const char *header, uint64_t start, uint64_t end, uint64_t expected_total);
#endif
