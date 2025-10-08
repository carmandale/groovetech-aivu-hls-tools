# VR180 YouTube Conversion - Status Report

**Date**: October 8, 2025  
**Status**: ✅ **RESOLVED** - Script fixed, metadata injection working, test file ready

## Problem Identified

The VR180 conversion script (`tools/aivu_to_vr180.sh`) was **failing silently** during metadata injection because:

1. **Root cause**: Script changes directory to `vargol-spatial-media/spatialmedia` but used relative path `.venv/bin/python3` which broke after the `cd` command
2. **Result**: MP4 files were being created WITHOUT VR180 metadata (st3d, sv3d atoms)
3. **Impact**: Files would upload to YouTube but play as flat side-by-side instead of immersive VR180

## Solution Implemented

**Fixed** `tools/aivu_to_vr180.sh` line 97-99:
```bash
# OLD (broken):
cd "$VARGOL_DIR"
python3 -m spatialmedia ...

# NEW (fixed):
PYTHON_BIN="$ORIG_DIR/.venv/bin/python3"
cd "$VARGOL_DIR"
"$PYTHON_BIN" -m spatialmedia ...
```

## Verification Complete

✅ **Test file created**: `build/kitten_vr180/Kitten_vr180_8640x4320_TEST.mp4` (172MB)
- Contains proper VR180 metadata atoms: `st3d` and `sv3d`
- True stereo with parallax (extracted left/right views from MV-HEVC)
- Resolution: 8640x4320 @ 60fps, H.264
- EQUI bounds set for VR180 (left: 0.25, right: 0.75)

✅ **Tools verified**:
- FFmpeg 7.1.1 with MV-HEVC support: Working
- Python venv with `uv` package manager: Working
- Vargol spatial-media fork: Working
- Bento4 (mp4dump): Installed

## Files Ready for YouTube Upload Testing

**IMPORTANT**: YouTube VR180 works best with **5760x2880** resolution. The script defaults to downscaling for compatibility.

### YouTube-Ready File (Needs to be Created)
**Recommended**: Run the script with default downscale:
```bash
./tools/aivu_to_vr180.sh media/Kitten.aivu build/kitten_vr180_youtube true
```
This will create: `Kitten_vr180_5760x2880.mp4` (~60-80MB, optimized for YouTube)

### Test File Created (NOT YouTube-optimized)
**File**: `build/kitten_vr180/Kitten_vr180_8640x4320_TEST.mp4`
- Size: 172MB
- Resolution: 8640x4320 (too high, may fail YouTube VR recognition)
- ⚠️ Use the downscaled version above instead

## Next Steps for YouTube Testing

1. **Upload test file** to YouTube as unlisted
2. **Wait 1-7 hours** for initial VR processing (flat SBS will show first)
3. **Verify VR badge appears** and head-tracking works
4. **If successful**: Process Dallas.aivu or NoBrainer.aivu for full-length content

## Script Performance Notes

- **Per-eye extraction + conversion** is compute-intensive:
  - Kitten.aivu (364MB, 25sec) = ~10 minutes total
  - Dallas.aivu (3.4GB, ~3min) = ~60-90 minutes est.
  - NoBrainer.aivu (3.8GB) = ~90-120 minutes est.
  
- **Recommended**: Test on short clips first, use env vars to tune quality/speed:
  ```bash
  PRESET=fast CRF=23 ./tools/aivu_to_vr180.sh input.aivu output_dir true
  ```

## Commit Required

The script fix needs to be committed:
```bash
git add tools/aivu_to_vr180.sh
git commit -m "fix: Use absolute path for Python venv in metadata injection

Resolves issue where cd into vargol directory broke relative .venv path,
causing metadata injection to fail silently. Files were created without
VR180 atoms (st3d, sv3d), resulting in flat SBS playback on YouTube.

Co-authored-by: factory-droid[bot] <138933559+factory-droid[bot]@users.noreply.github.com>"
```

## Summary

**Problem**: Metadata injection failing silently  
**Root Cause**: Broken relative path after `cd` command  
**Solution**: Use absolute path for Python interpreter  
**Result**: VR180 files now created with proper metadata  
**Status**: ✅ Ready for YouTube upload testing
