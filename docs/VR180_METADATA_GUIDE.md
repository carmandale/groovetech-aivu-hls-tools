# VR180 Metadata and Resolution Guide

## Critical: Why 5760x2880 for YouTube

**YouTube VR180 works best with 5760x2880 resolution.** While the script can create 8640x4320 files, they may not be recognized as VR content or take much longer to process.

### Resolution Details
- **Recommended**: 5760x2880 (2880x2880 per eye)
- **Maximum**: 8640x4320 (4320x4320 per eye) - may cause issues
- **Why**: YouTube's VR processing pipeline is optimized for the 5760x2880 size
- **Script Default**: `DOWNSCALE=true` (automatically creates 5760x2880)

## VR180 Metadata Explained

For YouTube to recognize a file as VR180, it needs specific MP4 atoms (metadata boxes):

### Required Atoms

1. **st3d** (Stereoscopic 3D)
   - Size: 8+5 bytes
   - Purpose: Tells YouTube this is stereo content
   - Value: `stereo_mode=2` (side-by-side left-right)

2. **sv3d** (Spherical Video)
   - Size: 8+73 bytes  
   - Contains: Projection info, layout, and spatial audio
   - Sub-atoms:
     - `svhd` - Spherical video header (required!)
     - `proj` - Projection type (equirectangular)
     - `equi` - Equirectangular bounds

3. **EQUI bounds** (inside sv3d)
   - **left**: 0x40000000 (0.25 in float) - Start of left half
   - **right**: 0xC0000000 (0.75 in float) - End of right half  
   - **top**: 0x00000000 (0.0) - Top of frame
   - **bottom**: 0xFFFFFFFF (~1.0) - Bottom of frame
   - **Purpose**: Defines which part of the frame is visible (180° not 360°)

### Why These Bounds Matter

For VR180 (half-sphere), the horizontal bounds are cropped to 0.25-0.75 because:
- Full frame: 5760 pixels wide (or 8640)
- Each eye: Half the width (2880 or 4320)
- VR180 uses the **middle 50%** of each eye's hemisphere
- This creates the proper 180° field of view

## Critical Issue: FFmpeg Loses Metadata

**Important**: When you use FFmpeg to downscale/transcode a video:
```bash
ffmpeg -i input_with_metadata.mp4 -vf scale=5760:2880 output.mp4
```

**The VR180 metadata atoms (st3d, sv3d) are NOT copied to the output!**

### Why This Happens
- FFmpeg preserves basic metadata (duration, codec tags, etc.)
- But MP4 spatial atoms are **not** in FFmpeg's standard copy list
- You need to **re-inject** the metadata after any transcode

### The Two-Step Process

If you need to downscale an already-created VR180 file:

**Step 1: Downscale with FFmpeg**
```bash
ffmpeg -y -i input_8640x4320_WITH_METADATA.mp4 \
  -vf "scale=5760:2880,fps=60" \
  -c:v libx264 -preset slow -crf 18 -pix_fmt yuv420p -movflags +faststart \
  -c:a copy \
  output_5760x2880_NO_METADATA.mp4
```

**Step 2: Re-inject Metadata**
```bash
cd tools/vargol-spatial-media/spatialmedia
python3 -m spatialmedia -i -s left-right -m equirectangular --degrees 180 \
  output_5760x2880_NO_METADATA.mp4 \
  output_5760x2880_WITH_METADATA.mp4
```

This is **exactly what the script does automatically** when `DOWNSCALE=true`.

## Verifying Metadata

### Quick Check (ffprobe)
```bash
ffprobe -v error -select_streams v:0 \
  -show_entries stream_tags=projection,stereo_mode \
  -of csv=p=0 your_file.mp4
```

**Expected output**: `equirectangular,left_right`

**If empty**: Metadata is missing! Re-inject.

### Detailed Check (Bento4)
```bash
mp4dump your_file.mp4 | grep -E '\[(st3d|sv3d|equi)\]' -A 5
```

**Expected**:
```
[st3d] size=8+5
[sv3d] size=8+73
```

**If these are missing**: The file will play as flat SBS on YouTube.

### Visual Test
Before uploading to YouTube, test locally:

**VLC**:
1. Open file in VLC
2. Tools → Effects and Filters → Video Effects → Advanced
3. Select "Spherical" mode: "Equirectangular"
4. Drag to pan - should show 180° view per eye with depth

**DeoVR/Skybox** (Quest/PC VR):
- Import file, select "180° SBS"
- Head tracking should work with 3D depth

## Common Issues

### Issue: File plays flat on YouTube
**Cause**: Missing st3d/sv3d atoms  
**Fix**: Re-inject metadata with vargol spatial-media

### Issue: No depth/3D effect
**Cause**: Using symmetric duplicate instead of true stereo extraction  
**Fix**: Use the current script which extracts view:0 and view:1 separately

### Issue: Wrong field of view
**Cause**: Incorrect EQUI bounds or v360 parameters  
**Fix**: Ensure bounds are 0.25-0.75 horizontal, v360 uses h_fov=180

### Issue: YouTube takes days to process
**Cause**: File is too large or wrong resolution  
**Fix**: Use 5760x2880 with `DOWNSCALE=true`

## Script Workflow

The `tools/aivu_to_vr180.sh` script handles everything:

1. **Extract stereo views** from MV-HEVC (view:0 left, view:1 right)
2. **Convert each eye** from fisheye to equirectangular (4320x4320)
3. **Stack side-by-side** (8640x4320 SBS)
4. **Downscale** to 5760x2880 (if DOWNSCALE=true, which is default)
5. **Inject VR180 metadata** (st3d, sv3d with proper EQUI bounds)
6. **Verify** metadata with ffprobe and optionally mp4dump

**Key**: Steps 4 and 5 must happen in order - downscale first, then inject.

## Environment Variables

Tune conversion quality/speed:

```bash
# Faster, lower quality (good for testing)
PRESET=fast CRF=23 ./tools/aivu_to_vr180.sh input.aivu output_dir true

# Slower, higher quality (production)
PRESET=veryslow CRF=16 ./tools/aivu_to_vr180.sh input.aivu output_dir true

# Use H.265 instead of H.264
CODEC=libx265 ./tools/aivu_to_vr180.sh input.aivu output_dir true
```

## References

- [YouTube VR180 Format](https://support.google.com/youtube/answer/6178631)
- [Google Spatial Media RFC](https://github.com/google/spatial-media/blob/master/docs/spherical-video-v2-rfc.md)
- [Vargol Spatial Media](https://github.com/Vargol/spatial-media) - Fixed --degree 180 support
- [Bento4 MP4 Tools](https://github.com/axiomatic-systems/Bento4)
