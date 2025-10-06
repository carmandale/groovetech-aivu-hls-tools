# GrooveTech AIVU → HLS Tools

## Overview

`aivu2hls.swift` produces an immersive-ready HTTP Live Streaming (HLS) package from a `.aivu` QuickTime file. The tool prefers Apple’s native HLS authoring utilities and falls back to `ffmpeg` when they are unavailable, while patching the master playlist with the metadata Vision Pro expects and wiring in AIME venue metadata.

## Requirements

- macOS with Swift toolchain (`/usr/bin/swift`)
- Either Apple’s HLS tools (`mediafilesegmenter`, `variantplaylistcreator`, `mediastreamvalidator`) or `ffmpeg`
- Python 3.9+ for the bundled `tools/extract_aime.py` helper
- `spatialmedia` CLI (`pip install spatialmedia`) for YouTube metadata injection
- Optional external AIME venue file (`.aime`) for `#EXT-X-IMMERSIVE-VIDEO`

## Prepare Source Media

Place your `.aivu` masters in `media/`. For the included presets, copy:

- `Kitten.aivu` → `media/Kitten.aivu`
- `NoBrainer.aivu` → `media/NoBrainer.aivu`

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
  --layout "CH-STEREO/PACK-NONE/PROJ-AIV" \
  --video-range PQ
```

Key flags:

- `-i/--input` – Source `.aivu` file (required)
- `-o/--output` – Output directory (required)
- `-n/--name` – Stream name (defaults to input filename)
- `-d/--duration` – Segment duration seconds (default `6.0`)
- `-r/--bitrates` – Comma-separated bandwidth ladder (defaults to `25e6,50e6,100e6`)
- `--aime` – Optional AIME venue file copied alongside playlists
- `--layout` – `REQ-VIDEO-LAYOUT` value (default `CH-STEREO/PACK-NONE/PROJ-AIV`)
- `--video-range` – Variant `VIDEO-RANGE` attribute (default `PQ`)
- `--content-type` – Session data `com.apple.private.content-type` value (default `Fully Immersive`)

If `--aime` is omitted, run `tools/extract_aime.py <input.aivu> <output.aime>` to pull the embedded venue payload out of the `.aivu` container. The script cleans the output directory before writing, generates variants, patches the master playlist (`#EXT-X-VERSION:12`, `REQ-VIDEO-LAYOUT`, optional `#EXT-X-IMMERSIVE-VIDEO`, `VIDEO-RANGE`), and invokes `mediastreamvalidator` when present.

## Makefile Shortcuts

`make kitten` and `make nobrainer` run the tool against the provided sample assets once the matching `.aivu` files are in `media/`. Each target extracts the venue AIME blob on the fly, invokes `aivu2hls.swift`, and runs `mediastreamvalidator --device visionpro`. Override defaults via environment variables:

```bash
SEGMENT_DURATION=4 BITRATES=20000000,40000000 make kitten
```

## Reference Material

`reference/apple_primary.m3u8` mirrors Apple’s sample immersive stream for quick comparison of playlist metadata.

## Validator Warning About Venue Session Data

Apple’s `mediastreamvalidator` cannot decode the proprietary binary `.aime` venue payload extracted from `.aivu` files. The validator reports the session-data parse failure as a `CAUTION`, but the `#EXT-X-SESSION-DATA` and `#EXT-X-IMMERSIVE-VIDEO` tags remain correct and Vision Pro ingests the stream successfully. Leave the binary venue reference in place for production playback; only replace it with a JSON stub if you explicitly need a warning-free validation log.

## Quick Commands

- Convert NoBrainer: `make nobrainer`
- Convert Kitten: `make kitten`
- Export a YouTube 180° stereo MP4: `make youtube MOVIE=NoBrainer`
- Serve locally for Vision Pro testing: `python3 -m http.server 8080 --directory build`
