#ifndef VIDRANE_BRIDGE_H
#define VIDRANE_BRIDGE_H
#include <stdint.h>
#include <stdbool.h>
uint32_t vidrane_media_kind(const char *filename);
uint32_t vidrane_api_version(void);
double vidrane_resume_position(double position, double duration);
bool vidrane_playback_finished(double position, double duration);
#endif
