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

The `.aivu` format uses **MV-HEVC (Multiview HEVC)** encoding with true stereo views (base layer + dependent view). YouTube does not support MV-HEVC, so conversion is required.

### Quick Start

```bash
# Via Makefile (recommended)
make youtube MOVIE=Kitten

# Or directly via script
./tools/aivu_to_vr180.sh media/Kitten.aivu build/kitten_vr180 true
```

### Conversion Workflow

The script (`tools/aivu_to_vr180.sh`) performs true stereo VR180 conversion:

1. **Extracts true stereo views** from MV-HEVC (view:0 left, view:1 right)
2. **Converts each eye** from fisheye to equirectangular (4320×4320 per eye)
3. **Stacks side-by-side** (8640×4320 SBS) preserving parallax depth
4. **Downscales to 5760×2880** (default, for YouTube compatibility)
5. **Downsamples to 60fps** (YouTube's maximum VR framerate)
6. **Injects VR180 metadata** (ST3D + SV3D boxes with EQUI bounds)

**Key Features:**

- **True Stereo**: Extracts separate left/right views for authentic 3D depth (not duplicated)
- **YouTube Optimized**: Defaults to 5760×2880 resolution for reliable VR recognition
- **Automatic Metadata**: Injects proper VR180 atoms (st3d, sv3d) with correct EQUI bounds (0.25-0.75)
- **Verification**: Validates metadata with ffprobe and optionally Bento4

### Technical Details

- **Input**: MV-HEVC 4320×4320 per eye @ 90fps (multilayer)
- **Extraction**: FFmpeg `-map 0:v:view:0` and `-map 0:v:view:1` for true stereo
- **Projection**: `v360=fisheye:equirect:h_fov=180:v_fov=180` per eye
- **Output**: H.264 5760×2880 @ 60fps Side-by-Side (2880×2880 per eye)
- **Encoding**: libx264 preset slow, CRF 18, yuv420p, ~40 Mbps
- **Metadata**: Vargol spatial-media with `--degree 180` for proper VR180 bounds

**Performance:** 
- Kitten (25 sec): ~10 minutes
- NoBrainer (2:49): ~90-120 minutes

**Documentation:**
- [VR180 Metadata Guide](docs/VR180_METADATA_GUIDE.md) - Detailed metadata explanation
- [YouTube VR180 Guide](docs/aivu-to-youtube-vr180-guide.md) - Complete workflow
- [VR180 Status](VR180_STATUS.md) - Recent fixes and testing

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
