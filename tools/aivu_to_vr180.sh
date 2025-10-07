#!/bin/bash
set -euo pipefail

require() { command -v "$1" >/dev/null 2>&1 || { echo >&2 "Error: $1 not found in PATH"; exit 1; }; }
require ffmpeg
require python3
require git

# Usage: ./tools/aivu_to_vr180.sh /path/to/input.aivu /path/to/output_dir [--downscale]
# Example: ./tools/aivu_to_vr180.sh media/Dallas.aivu build/dallas_vr180 true

INPUT_AIVU="$1"
OUTPUT_DIR="$2"
DOWNSCALE=${3:-false}

[ -f "$INPUT_AIVU" ] || { echo >&2 "Error: Input .aivu not found: $INPUT_AIVU"; exit 1; }
mkdir -p "$OUTPUT_DIR"

BASE_NAME=$(basename "$INPUT_AIVU" .aivu)
SBS_EQUIRECT="$OUTPUT_DIR/${BASE_NAME}_sbs_equirect_8640x4320.mp4"

# Env-tunable defaults
CODEC="${CODEC:-libx264}"
CRF="${CRF:-18}"
PRESET="${PRESET:-slow}"

# Fisheye SBS -> Equirect SBS, 90->60fps
ffmpeg -y -i "$INPUT_AIVU" \
  -vf "v360=input=fisheye:in_stereo=sbs:output=equirect:out_stereo=sbs:h_fov=180:v_fov=180:yaw=0:pitch=0:roll=0:w=8640:h=4320,fps=60" \
  -c:v "$CODEC" -preset "$PRESET" -crf "$CRF" -pix_fmt yuv420p -movflags +faststart \
  -c:a copy \
  "$SBS_EQUIRECT" || { echo >&2 "FFmpeg remap failed"; exit 1; }

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
if [[ ! -d "$VARGOL_DIR" ]]; then
  echo "Cloning Vargol spatial-media..."
  git clone https://github.com/Vargol/spatial-media.git "$PWD/tools/vargol-spatial-media"
  cd "$PWD/tools/vargol-spatial-media/spatialmedia"
  python3 -m pip install -r requirements.txt
  cd "$PWD"
fi

echo "Injecting VR180 metadata..."
python3 "$VARGOL_DIR/spatialmedia" -i -s left-right -m equirectangular --degree 180 "$INPUT_FOR_META" "$VR180_OUTPUT" \
  || { echo >&2 "Metadata injection failed"; exit 1; }

echo "Verifying metadata..."
ffprobe -v error -select_streams v:0 -show_entries stream_tags=projection,stereo_mode -of csv=p=0 "$VR180_OUTPUT"
if command -v mp4dump >/dev/null 2>&1; then
  mp4dump "$VR180_OUTPUT" | grep -A 10 -B 5 -i 'equi\|st3d\|sv3d'
fi

echo "Success: VR180 file ready at $VR180_OUTPUT"
echo "Upload to YouTube (unlisted) and wait 1-7 days for processing."
