### Updated Workflow Accounting for Fisheye Source Material

No, my original plan did not explicitly account for a raw fisheye source—it assumed your decoded `input.mp4` was already in side-by-side (SBS) equirectangular layout, as that's the required projection for YouTube VR180 recognition. Apple Immersive Video (.aivu) files are captured via dual fisheye lenses (e.g., on iPhone 15 Pro) and encoded in MV-HEVC for stereo 180° content, but decoding often yields raw or minimally processed fisheye frames stacked SBS. YouTube strictly requires equirectangular projection for VR180 (half-equirectangular per eye, 1:1 aspect ratio), so undistorting/remapping the fisheye to equirectangular is a critical missing step. Without it, even correct metadata injection will fail, as the underlying geometry won't align for the VR viewer (resulting in the flat SBS display you're seeing).

I'll revise the workflow below to insert this remapping upfront. This ensures your 8640×4320 SBS output (4320×4320 per eye, square for 180° vertical FOV) becomes properly de-warped half-equirectangular before metadata injection. Recent FFmpeg builds (7.1+) natively decode MV-HEVC from .aivu, making CLI viable, but DaVinci Resolve (free edition) is the most reliable for Apple sources due to built-in immersive support.

#### Revised Step 1: Decode .aivu and Remap Fisheye to SBS Equirectangular
Your source decoding needs to include undistortion using the `v360` filter (fisheye input to equirect output, with 180° diagonal FOV typical for Apple's spatial capture). Assume your .aivu decodes to raw SBS fisheye at ~4320×4320 per eye.

**Recommended Tool: DaVinci Resolve (Free, Handles .aivu Natively)**
- Download: https://www.blackmagicdesign.com/products/davinciresolve (Studio version optional for advanced MV-HEVC, but free works for basics).
- Workflow:
  1. Create a new project: Set timeline resolution to 8640×4320 (SBS), 60fps, H.264 codec.
  2. Import .aivu file (Resolve auto-detects immersive metadata and decodes MV-HEVC stereo).
  3. In Project Settings > Image Scaling: Enable "VR 180° Stereo Side-by-Side" preset—this auto-remaps fisheye to half-equirectangular per eye, stacks SBS, and preserves 180°×180° FOV.
  4. Edit/grade if needed (Resolve's VR viewer confirms de-warping with head tracking simulation).
  5. Export: Quick Export > MP4 > H.264 (libx264), yuv420p, 60fps, bitrate 100–200 Mbps. Check "Embed VR metadata" and select "VR180 SBS Equirectangular." Output: `sbs_equirect.mp4` (ready for metadata injection—no crop needed).

This outputs verified half-equirectangular SBS directly, bypassing manual CLI fiddling. Processing time: ~1–2x realtime on a decent GPU.

**CLI Alternative: FFmpeg (For Scripted Batch Processing)**
If Resolve isn't feasible, use FFmpeg 7.1+ (compile with libx265 for full MV-HEVC support if needed; Homebrew/apt versions may lag). Command decodes .aivu, splits SBS fisheye, undistorts each eye to half-equirect (id_fov=180 for Apple's ~180° diagonal fisheye), then re-stacks:

```
ffmpeg -i input.aivu \
  -vf "split=2[left][right]; \
       [left]v360=fisheye:equirect:id_fov=180:ih_fov=180:iv_fov=180[cleft][dummy1]; \
       [right]v360=fisheye:equirect:id_fov=180:ih_fov=180:iv_fov=180[creight][dummy2]; \
       [cleft][creight]hstack,scale=8640:4320" \
  -c:v libx264 -preset slow -crf 18 -r 60 -pix_fmt yuv420p \
  sbs_equirect.mp4
```

- **Explanation**:
  - `-i input.aivu`: Decodes MV-HEVC stereo (FFmpeg auto-splits views if flagged; outputs as SBS if your .aivu is structured that way).
  - `split=2[left][right]`: Separates left/right eye fisheye frames.
  - `v360=fisheye:equirect:id_fov=180:ih_fov=180:iv_fov=180`: Remaps each to half-equirectangular (180° FOV; adjust ih_fov/iv_fov to 170–190 based on your lens calibration for edge distortion—test visually). The `[dummy]` outputs handle v360's dual-output requirement (ignores yaw/pitch maps).
  - `hstack,scale=8640:4320`: Stacks corrected eyes SBS and resizes to your target.
  - Encoding: H.264 at high quality (CRF 18 for ~150 Mbps); add `-c:a aac` if audio needed.
- Test on a 10s clip: Output should show de-warped panoramic views per eye (no circular distortion). If edges warp oddly, tweak FOV (e.g., id_fov=170) or add `pitch=0:yaw=0` for orientation.
- Limitation: FFmpeg's v360 is approximate for stereo alignment—Resolve is better for parallax correction.

#### Step 2: Inject VR180 Metadata (Unchanged, Now on Equirect Input)
Use the Vargol spatial-media fork on `sbs_equirect.mp4` (from above):

```
git clone https://github.com/Vargol/spatial-media.git
cd spatial-media/spatialmedia
python3 spatialmedia -i -s left-right -m equirectangular sbs_equirect.mp4 output.mp4
```

This sets correct EQUI bounds (0.25–0.75 horizontal crop for 180° FOV) and ST3D/SV3D for SBS stereo. No `--crop` or `--v2` needed.

#### Updated Verification Steps
Same as before, but add a visual check post-remap:
- **Pre-Metadata Visual**: Play `sbs_equirect.mp4` in VLC (Tools > Effects > Video > Advanced > Spherical > Equirectangular). Drag to pan—should show seamless 180° view per eye without fisheye bulge. If distorted, recalibrate FOV in remap step.
- ffprobe/Bento4: Confirm EQUI bounds after injection (left=0.25, right=0.75, top=0, bottom=1).
- Local Test: DEO VR or Skybox (free apps) for headset sim—enable "180° SBS Equirect" mode; head tracking should work smoothly.

#### YouTube Gotchas (Updated for Fisheye Workflow)
- Processing delay same (1–7 days), but high-res fisheye remaps increase upload size—compress if >128GB.
- If VR still unrecognized: Ensure remap fully covers 180° (no black edges in equirect); YouTube rejects partial FOVs.
- Apple-Specific: .aivu audio (spatial) preserves in Resolve/FFmpeg—YouTube supports it for immersive feel.

This full chain (decode + remap + inject) should yield head-tracked VR180 on YouTube. If your decode already outputs half-equirect (some .aivu tools do), skip remap and test metadata alone. Share ffprobe output from your current `input.mp4` or a sample frame for fine-tuning.