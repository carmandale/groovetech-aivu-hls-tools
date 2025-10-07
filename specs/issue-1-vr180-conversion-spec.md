# Spec for GitHub Issue #1: Implement VR180 YouTube Conversion with Correct Metadata and Update Makefile/Script

## Objective
Fix the VR180 pipeline so .aivu → YouTube uploads are recognized as VR180 (head-tracked, stereo), with correct metadata (EQUI bounds 0.25-0.75, no "missing header" errors), using a clean, single canonical CLI workflow. Replace legacy incorrect spatial-media crop injection in Makefile with script delegation.

## Architectural Decisions
- Use FFmpeg v360 in a single mapping pass: fisheye SBS → equirect SBS (h_fov/v_fov=180, yaw/pitch/roll=0 for Apple orientation).
- Use Vargol’s spatial-media fork for metadata injection with `-m equirectangular --degree 180` to auto-set VR180 EQUI bounds (left=0.25, right=0.75, top=0.0, bottom=1.0), ST3D stereo=2, SV3D layout=1, and svhd header.
- Centralize logic in `tools/aivu_to_vr180.sh` (bash for low deps). Makefile "youtube" target delegates to script.
- Enforce 90→60fps downsample (YouTube VR max); prefer `-c:a copy` for audio (fallback to AAC if incompatible).
- No Python wrapper (defer); focus on robust bash + env vars (CODEC/CRF/PRESET/VARGOL_DIR).

## Scope of Changes
- Modify: Makefile (youtube target).
- Modify: tools/aivu_to_vr180.sh (single v360, preflights, env vars, audio fallback doc).
- Modify: docs/aivu-to-youtube-vr180-guide.md (update examples, add Makefile integration, remove crop refs).
- Modify: .gitignore (ignore Vargol fork, pycache, build/MP4s).
- No other files (e.g., no Swift changes).

## Detailed Changes

### 1. Makefile: Delegate youtube target to script
**Location**: Makefile, replace entire `youtube:` target body.

**Rationale**: Current uses invalid `--crop 8640:4320:8640:8640:0:2160` (malformed full_h/top, leads to EQUI=0 and header errors). Script ensures correct Vargol injection.

**New Target**:
```
youtube:
	@[ "$(MOVIE)" != "" ] || (echo "Set MOVIE=<basename without extension> (e.g. MOVIE=NoBrainer)" && exit 1)
	@MOVIE_INPUT="media/$(MOVIE).aivu"; \
	 [ -f "$$MOVIE_INPUT" ] || (echo "Missing $$MOVIE_INPUT. Copy $(MOVIE).aivu into media/." && exit 1); \
	 MOVIE_LOWER=$$(echo "$(MOVIE)" | tr '[:upper:]' '[:lower:]'); \
	 OUTPUT_DIR="$(BUILD_DIR)/$${MOVIE_LOWER}_vr180"; \
	 mkdir -p "$$OUTPUT_DIR"; \
	 echo "Converting $$MOVIE_INPUT to YouTube VR180..."; \
	 ./tools/aivu_to_vr180.sh "$$MOVIE_INPUT" "$$OUTPUT_DIR" $(DOWNSCALE)
```

**Interface**:
- Vars: MOVIE (req, basename); DOWNSCALE (opt, true for 5760x2880).
- Outputs: `$(BUILD_DIR)/{movie_lower}_vr180/{movie}_vr180.mp4` (or `_vr180_5760x2880.mp4`).

**Side Effects**: Breaks old behavior (intentional); add `youtube-clean:` target if needed (`rm -rf $(BUILD_DIR)/*_vr180`).

### 2. tools/aivu_to_vr180.sh: Single-pass v360 and robust injection
**Location**: tools/aivu_to_vr180.sh; replace FFmpeg block, add preflights/env vars.

**Rationale**: Single v360 reduces errors vs. split/hstack; Vargol `--degree 180` fixes bounds. Preflights prevent silent fails; env vars tune quality.

**Key Snippets**:
- **Prologue/Preflights**:
```
#!/bin/bash
set -euo pipefail

require() { command -v "$1" >/dev/null 2>&1 || { echo >&2 "Error: $1 not found in PATH"; exit 1; }; }
require ffmpeg
require python3
require git

INPUT_AIVU="$1"
OUTPUT_DIR="$2"
DOWNSCALE=${3:-false}

[ -f "$INPUT_AIVU" ] || { echo >&2 "Error: Input .aivu not found: $INPUT_AIVU"; exit 1; }
mkdir -p "$OUTPUT_DIR"
```

- **Single v360 Remap** (replace split/hstack):
```
BASE_NAME=$(basename "$INPUT_AIVU" .aivu)
SBS_EQUIRECT="$OUTPUT_DIR/${BASE_NAME}_sbs_equirect_8640x4320.mp4"

# Env-tunable defaults
CODEC="${CODEC:-libx264}"
CRF="${CRF:-18}"
PRESET="${PRESET:-slow}"

# 90→60fps, fisheye SBS → equirect SBS
ffmpeg -y -i "$INPUT_AIVU" \
  -vf "v360=input=fisheye:in_stereo=sbs:output=equirect:out_stereo=sbs:h_fov=180:v_fov=180:yaw=0:pitch=0:roll=0:w=8640:h=4320,fps=60" \
  -c:v "$CODEC" -preset "$PRESET" -crf "$CRF" -pix_fmt yuv420p -movflags +faststart \
  -c:a copy \
  "$SBS_EQUIRECT" || { echo >&2 "FFmpeg remap failed"; exit 1; }

INPUT_FOR_META="$SBS_EQUIRECT"
VR180_OUTPUT="$OUTPUT_DIR/${BASE_NAME}_vr180.mp4"
```

- **Downscale** (conditional, as-is):
```
if [[ "$DOWNSCALE" == true ]]; then
  DOWNSCALED="$OUTPUT_DIR/${BASE_NAME}_sbs_equirect_5760x2880.mp4"
  ffmpeg -y -i "$SBS_EQUIRECT" -vf "scale=5760:2880,fps=60" \
    -c:v "$CODEC" -preset "$PRESET" -crf "$CRF" -pix_fmt yuv420p -movflags +faststart \
    -c:a copy \
    "$DOWNSCALED" || { echo >&2 "Downscale failed"; exit 1; }
  INPUT_FOR_META="$DOWNSCALED"
  VR180_OUTPUT="$OUTPUT_DIR/${BASE_NAME}_vr180_5760x2880.mp4"
fi
# Audio fallback note: If copy fails, re-run with -c:a aac -b:a 192k
```

- **Vargol Injection** (keep, with override):
```
VARGOL_DIR="${VARGOL_DIR:-$PWD/tools/vargol-spatial-media/spatialmedia}"
if [[ ! -d "$VARGOL_DIR" ]]; then
  echo "Cloning Vargol spatial-media..."
  git clone https://github.com/Vargol/spatial-media.git "$PWD/tools/vargol-spatial-media"
  python3 -m pip install -r "$PWD/tools/vargol-spatial-media/spatialmedia/requirements.txt"
fi

echo "Injecting VR180 metadata..."
python3 "$VARGOL_DIR/spatialmedia" -i -s left-right -m equirectangular --degree 180 "$INPUT_FOR_META" "$VR180_OUTPUT" \
  || { echo >&2 "Metadata injection failed"; exit 1; }
```

- **Verification** (lightweight):
```
ffprobe -v error -select_streams v:0 -show_entries stream_tags=projection,stereo_mode -of csv=p=0 "$VR180_OUTPUT"
if command -v mp4dump >/dev/null 2>&1; then
  mp4dump "$VR180_OUTPUT" | grep -A 10 -B 5 -i 'equi\|st3d\|sv3d'
fi
```

**Interface**: Unchanged args; env vars for tuning. Exit 0 on success.

**Side Effects**: Clones Vargol on first run; 8K heavy—doc in guide.

### 3. docs/aivu-to-youtube-vr180-guide.md: Update examples/guidance
**Location**: docs/aivu-to-youtube-vr180-guide.md; replace FFmpeg/metadata snippets, add Makefile section.

**Rationale**: Align docs with script; remove crop to prevent errors.

**Snippets**:
- **FFmpeg** (replace old):
```
ffmpeg -y -i input.aivu \
  -vf "v360=input=fisheye:in_stereo=sbs:output=equirect:out_stereo=sbs:h_fov=180:v_fov=180:yaw=0:pitch=0:roll=0:w=8640:h=4320,fps=60" \
  -c:v libx264 -preset slow -crf 18 -pix_fmt yuv420p -movflags +faststart \
  -c:a copy sbs_equirect_8640x4320.mp4
```

- **Metadata** (replace):
```
python3 tools/vargol-spatial-media/spatialmedia/spatialmedia -i -s left-right -m equirectangular --degree 180 sbs_equirect_8640x4320.mp4 output_vr180.mp4
```

- **New Makefile Section**:
```
## Makefile Integration
make youtube MOVIE=Dallas
# With downscale:
make youtube MOVIE=Dallas DOWNSCALE=true
```

- **Verification** (add expected):
```
ffprobe ... # Expect: equirectangular,left_right
mp4dump ... | grep EQUI # left: 0x40000000 (0.25), right: 0xC0000000 (0.75), top: 0x00000000, bottom: 0xFFFFFFFF (~1.0)
```

**Advanced Note**: "If single v360 misaligns, use per-eye split/hstack fallback (see script comments)."

### 4. .gitignore: Ignore artifacts
**Location**: .gitignore; append lines.

**Add**:
```
tools/vargol-spatial-media/
tools/vargol-spatial-media/**/__pycache__/
__pycache__/
*.pyc
build/
*.mp4
```

## Critical Notes
- v360: input=fisheye/in_stereo=sbs → output=equirect/out_stereo=sbs; h_fov/v_fov=180 for Apple 180° FOV.
- Vargol: --degree 180 auto EQUI crop for VR180; V2 (SV3D/ST3D/svhd).
- Downsample: fps=60 enforces 90→60 (YouTube req).
- Test: On Dallas.aivu (trim to 10s for speed); verify bounds, upload unlisted, monitor 1-24h for VR.

## Potential Side Effects/Mitigations
- Heavy compute/disk: Use short clips for testing; env vars tune (e.g., CRF=23 for faster).
- v360 missing: Preflight fails; install Homebrew FFmpeg.
- Audio fail: Doc fallback re-run with AAC.

This spec implements a reliable VR180 pipeline, fixing metadata for YouTube recognition.
