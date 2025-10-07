#!/bin/bash

# Usage: ./tools/aivu_to_vr180.sh /path/to/input.aivu /path/to/output_dir [--downscale]
# Example: ./tools/aivu_to_vr180.sh media/Dallas.aivu build/dallas_vr180 true

set -e  # Exit on error

INPUT_AIVU="$1"
OUTPUT_DIR="$2"
DOWNSCALE=${3:-false}

if [[ ! -f "$INPUT_AIVU" ]]; then
  echo "Error: Input .aivu not found: $INPUT_AIVU"
  exit 1
fi

mkdir -p "$OUTPUT_DIR"
BASE_NAME=$(basename "$INPUT_AIVU" .aivu)
SBS_EQUIRECT="$OUTPUT_DIR/${BASE_NAME}_sbs_equirect_8640x4320.mp4"
VR180_OUTPUT="$OUTPUT_DIR/${BASE_NAME}_vr180.mp4"

# Step 1: Decode/Remap with FFmpeg (90fps → 60fps, 8640x4320)
echo "Remapping fisheye to SBS equirectangular..."
ffmpeg -i "$INPUT_AIVU" \
  -vf "split=2[left][right]; \
       [left]v360=fisheye:equirect:id_fov=180:ih_fov=180:iv_fov=180:yaw=0:pitch=0:roll=0:ih_cx=0.5:iv_cy=0.5[left_remap][dummy1]; \
       [right]v360=fisheye:equirect:id_fov=180:ih_fov=180:iv_fov=180:yaw=0:pitch=0:roll=0:ih_cx=0.5:iv_cy=0.5[right_remap][dummy2]; \
       [left_remap][right_remap]hstack,scale=8640:4320,fps=60" \
  -c:v libx264 -preset slow -crf 18 -r 60 -pix_fmt yuv420p -b:v 150M \
  -c:a aac -movflags +faststart "$SBS_EQUIRECT" || { echo "FFmpeg remap failed"; exit 1; }

INPUT_FOR_META="$SBS_EQUIRECT"

# Optional Downscale
if [[ "$DOWNSCALE" == true ]]; then
  DOWNSCALED="$OUTPUT_DIR/${BASE_NAME}_sbs_equirect_5760x2880.mp4"
  echo "Downscaling to 5760x2880..."
  ffmpeg -i "$SBS_EQUIRECT" -vf scale=5760:2880,fps=60 \
    -c:v libx264 -preset slow -crf 18 -b:v 120M -pix_fmt yuv420p -movflags +faststart \
    "$DOWNSCALED" || { echo "Downscale failed"; exit 1; }
  INPUT_FOR_META="$DOWNSCALED"
  VR180_OUTPUT="$OUTPUT_DIR/${BASE_NAME}_vr180_5760x2880.mp4"
fi

# Step 2: Inject Metadata (Vargol; assumes cloned to tools/vargol-spatial-media)
VARGOL_DIR="$PWD/tools/vargol-spatial-media/spatialmedia"  # Adjust if cloned elsewhere
if [[ ! -d "$VARGOL_DIR" ]]; then
  echo "Cloning Vargol spatial-media..."
  git clone https://github.com/Vargol/spatial-media.git "$PWD/tools/vargol-spatial-media"
  cd "$PWD/tools/vargol-spatial-media/spatialmedia" && pip install -r requirements.txt
  cd "$PWD"
fi

echo "Injecting VR180 metadata..."
python3 "$VARGOL_DIR/spatialmedia" -i -s left-right -m equirectangular --degree 180 "$INPUT_FOR_META" "$VR180_OUTPUT" || { echo "Metadata injection failed"; exit 1; }

# Step 3: Basic Verification
echo "Verifying metadata..."
ffprobe -v error -select_streams v:0 -show_entries stream_tags=projection,stereo_mode -of csv=p=0 "$VR180_OUTPUT"
ffprobe -v warning "$VR180_OUTPUT" 2>&1 | grep -i spherical || echo "No spherical warnings (good)"

# Optional: Full Bento4 check (uncomment if bento4 installed)
# mp4dump "$VR180_OUTPUT" | grep -A 10 -B 5 'EQUI\|st3d\|sv3d' || echo "Detailed check: Run manually"

echo "Success: VR180 file ready at $VR180_OUTPUT"
echo "Upload to YouTube (unlisted) and wait 1-7 days for processing."
