# Local file manager (iOS)

The managed library lives inside the application sandbox at Documents/Media.
Importing from iOS Files copies items into that directory, leaving the
original external content untouched.

## Implemented

- Browse nested directories and create new directories at any level.
- Import files or folders into the currently open folder.
- Copy, move, rename and delete files and entire directories.
- Reject silent overwriting on rename and move. Copies receive a numeric
  suffix when names conflict.
- Prevent moving a directory into itself or its descendants.
- Filter and sort files; search within the current folder.
- Show file information and share files via iOS Share Sheet.
- Permanently delete only after confirmation.
- All operations are restricted to the managed Media tree.

## Playlist/history compatibility

Playlist entries and viewing checkpoints are now keyed by paths *relative*
to Media. Example: TV/Show/E01.mkv instead of just E01.mkv.

Old flat filenames in the Media root keep the same identifier, so old
playlists and history do not need a migration. When files or folders are
moved or renamed, all matching entries in playlists and watch history are
rewritten. Copied files do not inherit history.

## Limitations

No trash/undo, multi-item selection, archive extraction, or persistent
external-folder bookmarks yet. Large folder operations run synchronously.
Symlink targets are excluded from recursive library enumeration.
These flows have compiled on CI but need on-device validation later.
