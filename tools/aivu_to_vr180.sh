#!/bin/bash
set -euo pipefail

require() { command -v "$1" >/dev/null 2>&1 || { echo >&2 "Error: $1 not found in PATH"; exit 1; }; }
require ffmpeg
require python3
require git
require uv

# Usage: ./tools/aivu_to_vr180.sh /path/to/input.aivu /path/to/output_dir [--downscale]
# Example: ./tools/aivu_to_vr180.sh media/Dallas.aivu build/dallas_vr180 true

INPUT_AIVU="$1"
OUTPUT_DIR="$2"
DOWNSCALE=${3:-true}  # Default true for YouTube compatibility (5760x2880)

[ -f "$INPUT_AIVU" ] || { echo >&2 "Error: Input .aivu not found: $INPUT_AIVU"; exit 1; }
mkdir -p "$OUTPUT_DIR"

BASE_NAME=$(basename "$INPUT_AIVU" .aivu)
LEFT_EYE="$OUTPUT_DIR/${BASE_NAME}_left_fisheye.mov"
RIGHT_EYE="$OUTPUT_DIR/${BASE_NAME}_right_fisheye.mov"
LEFT_EQUI="$OUTPUT_DIR/${BASE_NAME}_left_equirect_4320x4320.mp4"
RIGHT_EQUI="$OUTPUT_DIR/${BASE_NAME}_right_equirect_4320x4320.mp4"
SBS_EQUIRECT="$OUTPUT_DIR/${BASE_NAME}_sbs_equirect_8640x4320.mp4"

# Env-tunable defaults
CODEC="${CODEC:-libx264}"
CRF="${CRF:-18}"
PRESET="${PRESET:-slow}"

echo "Step 1: Extracting left eye from MV-HEVC (view:0)..."
ffmpeg -y -i "$INPUT_AIVU" -map 0:v:view:0 -c copy -tag:v hvc1 "$LEFT_EYE" \
  || { echo >&2 "Left eye extraction failed"; exit 1; }

echo "Step 2: Extracting right eye from MV-HEVC (view:1)..."
ffmpeg -y -i "$INPUT_AIVU" -map 0:v:view:1 -c copy -tag:v hvc1 "$RIGHT_EYE" \
  || { echo >&2 "Right eye extraction failed"; exit 1; }

echo "Step 3: Converting left eye fisheye to equirectangular..."
ffmpeg -y -i "$LEFT_EYE" \
  -vf "v360=input=fisheye:output=equirect:h_fov=180:v_fov=180:w=4320:h=4320:yaw=0:pitch=0:roll=0,fps=60" \
  -c:v "$CODEC" -preset "$PRESET" -crf "$CRF" -pix_fmt yuv420p -movflags +faststart \
  "$LEFT_EQUI" || { echo >&2 "Left eye v360 conversion failed"; exit 1; }

echo "Step 4: Converting right eye fisheye to equirectangular..."
ffmpeg -y -i "$RIGHT_EYE" \
  -vf "v360=input=fisheye:output=equirect:h_fov=180:v_fov=180:w=4320:h=4320:yaw=0:pitch=0:roll=0,fps=60" \
  -c:v "$CODEC" -preset "$PRESET" -crf "$CRF" -pix_fmt yuv420p -movflags +faststart \
  "$RIGHT_EQUI" || { echo >&2 "Right eye v360 conversion failed"; exit 1; }

echo "Step 5: Stacking left and right eyes to side-by-side (with audio from original)..."
ffmpeg -y -i "$LEFT_EQUI" -i "$RIGHT_EQUI" -i "$INPUT_AIVU" \
  -filter_complex "[0:v][1:v]hstack[v]" \
  -map "[v]" -map 2:a? \
  -c:v "$CODEC" -preset "$PRESET" -crf "$CRF" -pix_fmt yuv420p -movflags +faststart \
  -c:a copy \
  "$SBS_EQUIRECT" || { echo >&2 "SBS hstack failed"; exit 1; }

# Clean up intermediate files
rm -f "$LEFT_EYE" "$RIGHT_EYE" "$LEFT_EQUI" "$RIGHT_EQUI"

INPUT_FOR_META="$SBS_EQUIRECT"
VR180_OUTPUT="$OUTPUT_DIR/${BASE_NAME}_vr180.mp4"

if [[ "$DOWNSCALE" == true ]]; then
  DOWNSCALED="$OUTPUT_DIR/${BASE_NAME}_sbs_equirect_5760x2880.mp4"
  ffmpeg -y -i "$SBS_EQUIRECT" -vf "scale=5760:2880,fps=60" \
    -c:v "$CODEC" -preset "$PRESET" -crf "$CRF" -pix_fmt yuv420p -movflags +faststart \
    -c:a copy \
    "$DOWNSCALED" || { echo >&2 "Downscale failed"; exit 1; }
  INPUT_FOR_META="$DOWNSCALED"
  VR180_OUTPUT="$OUTPUT_DIR/${BASE_NAME}_vr180_5760x2880.mp4"
fi

# Audio fallback: If copy fails above, re-run FFmpeg with -c:a aac -b:a 192k

VARGOL_DIR="${VARGOL_DIR:-$PWD/tools/vargol-spatial-media/spatialmedia}"
VENV_DIR="$PWD/.venv"

if [[ ! -d "$VARGOL_DIR" ]]; then
  echo "Cloning Vargol spatial-media..."
  git clone https://github.com/Vargol/spatial-media.git "$PWD/tools/vargol-spatial-media"
fi

if [[ ! -d "$VENV_DIR" ]]; then
  echo "Creating Python virtual environment with uv..."
  uv venv "$VENV_DIR"
fi

echo "Installing spatialmedia module..."
source "$VENV_DIR/bin/activate"
uv pip install -e "$PWD/tools/vargol-spatial-media"

echo "Injecting VR180 metadata..."
ORIG_DIR="$PWD"
PYTHON_BIN="$ORIG_DIR/.venv/bin/python3"
cd "$VARGOL_DIR"
"$PYTHON_BIN" -m spatialmedia -i -s left-right -m equirectangular --degree 180 "$ORIG_DIR/$INPUT_FOR_META" "$ORIG_DIR/$VR180_OUTPUT" \
  || { echo >&2 "Metadata injection failed"; cd "$ORIG_DIR"; exit 1; }
cd "$ORIG_DIR"

echo "Verifying metadata..."
ffprobe -v error -select_streams v:0 -show_entries stream_tags=projection,stereo_mode -of csv=p=0 "$VR180_OUTPUT"
if command -v mp4dump >/dev/null 2>&1; then
  mp4dump "$VR180_OUTPUT" | grep -A 10 -B 5 -i 'equi\|st3d\|sv3d'
fi

echo "Success: VR180 file ready at $VR180_OUTPUT"
echo "Upload to YouTube (unlisted) and wait 1-7 days for processing."
