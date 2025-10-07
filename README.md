# GrooveTech AIVU → HLS Tools

## Overview

`aivu2hls.swift` produces Vision Pro–ready HTTP Live Streaming (HLS) packages from `.aivu` (Apple Immersive Video Universal) files using Apple's official tooling and the `ImmersiveMediaSupport` framework. The tool automatically extracts venue metadata, segments with `mediafilesegmenter` (preserving all tracks including critical PresentationDescriptor metadata), and generates properly formatted master playlists.

## Requirements

- macOS 26.0+ with Xcode 26.0+ (Swift 6.2) for `ImmersiveMediaSupport` framework
- Apple's HLS tools: `mediafilesegmenter`, `mediastreamvalidator` (download from developer.apple.com/download)
- `ffprobe` (optional, for metadata probing in master playlists)
- Python 3.9+ for YouTube exports via `tools/spatial-media`

## Prepare Source Media

Place your `.aivu` masters in `media/`:

- `Kitten.aivu` → `media/Kitten.aivu`
- `NoBrainer.aivu` → `media/NoBrainer.aivu`
- `Dallas.aivu` → `media/Dallas.aivu`

## Usage

Make the script executable and invoke it directly:

```bash
chmod +x aivu2hls.swift
./aivu2hls.swift \
  -i media/Kitten.aivu \
  -o build/kitten \
  -n kitten \
  -d 6 \
  -r 25000000,50000000,100000000 \
  --layout "CH-STEREO/PACK-NONE/PROJ-AIV" \
  --video-range PQ
```

Key flags:

- `-i/--input` – Source `.aivu` file (required)
- `-o/--output` – Output directory (required)
- `-n/--name` – Stream name (defaults to input filename)
- `-d/--duration` – Segment duration seconds (default `6`)
- `-r/--bitrates` – Comma-separated bandwidth ladder (defaults to `25000000,50000000,100000000`)
- `--layout` – `REQ-VIDEO-LAYOUT` value (default `CH-STEREO/PACK-NONE/PROJ-AIV`)
- `--video-range` – Variant `VIDEO-RANGE` attribute (default `PQ`)
- `--content-type` – Session data `com.apple.private.content-type` value (default `Fully Immersive`)

The tool automatically:
1. Extracts `VenueDescriptor` from `.aivu` using `ImmersiveMediaSupport` framework
2. Saves venue data as `.aime` file alongside playlists
3. Segments with `mediafilesegmenter` (preserves video, audio, and metadata tracks)
4. Builds master playlist with HLS v12 tags and immersive metadata
5. Validates output with `mediastreamvalidator --device visionpro`

## Makefile Shortcuts

`make kitten`, `make nobrainer`, and `make dallas` build complete HLS packages. Each target invokes `aivu2hls.swift` which handles venue extraction, segmentation, and validation. Override defaults via environment variables:

```bash
SEGMENT_DURATION=4 BITRATES=20000000,40000000 make kitten
```

## Reference Material

`reference/apple_primary.m3u8` mirrors Apple's sample immersive stream for quick comparison of playlist metadata.

## Validator Warning About Venue Session Data

Apple's `mediastreamvalidator` cannot decode the proprietary binary `.aime` venue payload extracted from `.aivu` files. The validator reports the session-data parse failure as a `CAUTION`, but the `#EXT-X-SESSION-DATA` and `#EXT-X-IMMERSIVE-VIDEO` tags remain correct and Vision Pro ingests the stream successfully. Leave the binary venue reference in place for production playback; only replace it with a JSON stub if you explicitly need a warning-free validation log.

## YouTube VR180 Export

The `.aivu` format uses **MV-HEVC (Multiview HEVC)** encoding – both eyes are encoded in a single 4320×4320 stream using HEVC's multiview extension with frame-alternate stereo packing. YouTube does not support MV-HEVC, so direct stream copying fails.

### Conversion Workflow

The `youtube` Makefile target properly converts MV-HEVC to YouTube's VR180 specification:

```bash
make youtube MOVIE=Kitten
```

**What it does:**

1. **Decodes MV-HEVC** frame-alternate stereo using ffmpeg's `stereo3d` filter
2. **Converts to Side-by-Side layout** (8640×4320) – YouTube's preferred VR180 format
3. **Downsamples to 60fps** – YouTube's maximum supported framerate (from 90fps source)
4. **Re-encodes with H.264** at 80 Mbps – YouTube's recommended VR180 bitrate
5. **Injects v2 metadata** (ST3D + SV3D boxes) with left-right stereo and VR180 crop parameters

**Technical Details:**

- **Input**: MV-HEVC 4320×4320 per eye @ 90fps (frame-alternate)
- **Filter**: `stereo3d=al:sbsl` (alternating → side-by-side left-first)
- **Output**: H.264 8640×4320 @ 60fps Side-by-Side
- **Encoding**: libx264 preset medium, 80Mbps, yuv420p
- **Metadata**: `--v2 --stereo=left-right --crop 8640:4320:8640:8640:0:2160`

**Why Side-by-Side at 60fps?**

- YouTube recommends Side-by-Side over top-bottom (better bandwidth efficiency)
- 60fps is YouTube's maximum for VR content; 90fps gets downsampled anyway
- Pre-converting to 60fps ensures optimal quality and faster processing

**Performance:** Encoding takes ~7-10 minutes per 3-minute video (full re-encode required).

## Quick Commands

- Convert NoBrainer: `make nobrainer`
- Convert Kitten: `make kitten`
- Convert Dallas: `make dallas`
- Export a YouTube 180° stereo MP4: `make youtube MOVIE=Dallas`
- Serve locally for Vision Pro testing: `python3 -m http.server 8080 --directory build`

## Implementation Notes

The tool uses modern Apple frameworks and official tooling:

- **`ImmersiveMediaSupport`**: Extracts `VenueDescriptor` and AIME data using proper APIs (no binary parsing)
- **`mediafilesegmenter`**: Preserves all tracks (video, audio, metadata) including critical `PresentationDescriptor` commands
- **`mediastreamvalidator`**: Validates HLS output for Vision Pro compatibility

The metadata track contains timed `PresentationDescriptor` commands (setCamera, fade, etc.) that Vision Pro requires for proper immersive rendering. Previous ffmpeg-based approaches failed because they omitted this track.
