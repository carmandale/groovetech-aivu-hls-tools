# GrooveTech AIVU → HLS Tools

## Overview

`aivu2hls.swift` produces an immersive-ready HTTP Live Streaming (HLS) package from a `.aivu` QuickTime file. The tool prefers Apple’s native HLS authoring utilities and falls back to `ffmpeg` when they are unavailable, while patching the master playlist with the metadata Vision Pro expects.

## Requirements

- macOS with Swift toolchain (`/usr/bin/swift`)
- Either Apple’s HLS tools (`mediafilesegmenter`, `variantplaylistcreator`, `mediastreamvalidator`) or `ffmpeg`
- Optional AIME venue file (`.aime`) for `#EXT-X-IMMERSIVE-VIDEO`

## Usage

Make the script executable and invoke it directly:

```bash
chmod +x aivu2hls.swift
./aivu2hls.swift \
  -i media/Kitten.aivu \
  -o build/kitten \
  -n kitten \
  -d 6.0 \
  -r 25000000,50000000,100000000 \
  --layout "CH=STEREO/PROJ=AIV" \
  --video-range PQ
```

Key flags:

- `-i/--input` – Source `.aivu` file (required)
- `-o/--output` – Output directory (required)
- `-n/--name` – Stream name (defaults to input filename)
- `-d/--duration` – Segment duration seconds (default `6.0`)
- `-r/--bitrates` – Comma-separated bandwidth ladder (defaults to `25e6,50e6,100e6`)
- `--aime` – Optional AIME venue file copied alongside playlists
- `--layout` – `REQ-VIDEO-LAYOUT` value (default `CH=STEREO/PROJ=AIV`)
- `--video-range` – Variant `VIDEO-RANGE` attribute (default `PQ`)

The script cleans the output directory before writing, generates variants, patches the master playlist (`#EXT-X-VERSION:12`, `REQ-VIDEO-LAYOUT`, optional `#EXT-X-IMMERSIVE-VIDEO`, `VIDEO-RANGE`), and invokes `mediastreamvalidator` when present.

## Makefile Shortcuts

`make kitten` and `make nobrainer` run the tool against the provided sample assets. Override defaults via environment variables:

```bash
SEGMENT_DURATION=4 BITRATES=20000000,40000000 make kitten
```

## Reference Material

`reference/apple_primary.m3u8` mirrors Apple’s sample immersive stream for quick comparison of playlist metadata.
