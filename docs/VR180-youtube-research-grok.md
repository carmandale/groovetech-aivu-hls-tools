### 1. Exact spatial-media Command with Correct Parameters (or Alternative Tool)

The core issue with your current command is that the original Google `spatial-media` tool does not natively support VR180 workflows—it was primarily designed for full 360° videos. Your `--crop 8640:4320:8640:8640:0:2160` parameter is malformed for VR180: the `full_h=8640` (double the actual height) and `top=2160` (a pixel offset) result in EQUI bounds defaulting to all 0s, which signals a full 360° projection to YouTube instead of a cropped 180°×180° FOV. This causes the flat SBS display and lack of VR recognition.

For VR180 side-by-side (SBS) equirectangular videos like yours (8640×4320, left-right layout, 180°×180° FOV), use **equirectangular projection** (not fisheye or mesh, unless your source is raw fisheye). The bounds must be set to left=0.25, top=0, right=0.75, bottom=1.0 (in normalized coordinates, or ~1073741824 / 0 / 3221225472 / 4294967296 in 32-bit fixed-point integers) to indicate the half-sphere crop. No manual `--crop` is needed if using the right tool variant—it handles this automatically.

#### Recommended Workflow: Use the Vargol Fork of spatial-media
This is a modified version of Google's tool specifically for VR180, merging V2 spherical metadata with VR180 hacks. It automatically sets the correct EQUI bounds for 180° FOV without `--crop` or `--v2` flags (V2 is default). Download and run it in your bash environment:

```
git clone https://github.com/Vargol/spatial-media.git
cd spatial-media/spatialmedia
python3 spatialmedia -i -s left-right -m equirectangular input.mp4 output.mp4
```

- `-i`: Inject metadata (copies streams, no re-encode).
- `-s left-right`: Sets ST3D stereo mode to 2 (side-by-side, left first).
- `-m equirectangular`: Sets projection to equirectangular with auto VR180 bounds (left=0.25, right=0.75 for horizontal 180°; top=0, bottom=1 for full vertical).
- Output: MP4 with injected SV3D/ST3D/EQUI boxes.

This matches your specs (H.264, yuv420p, 60fps) and should resolve the "Missing spherical video header" warning in ffprobe. Test on a short clip first—processing takes seconds.

#### Alternative Tool: FFmpeg with Metadata (Quick Hack, Less Reliable)
If the fork fails (e.g., Python deps), use FFmpeg to inject basic tags (but it may not set EQUI bounds perfectly, leading to inconsistent YouTube recognition):
```
ffmpeg -i input.mp4 -c copy -metadata:s:v:0 stereo_mode="left_right" -metadata:s:v:0 projection="equirectangular" output.mp4
```
Then re-inject with the fork above. FFmpeg alone often strips complex boxes like EQUI bounds.

#### Alternative Approach: DaVinci Resolve (Free, No CLI)
If CLI isn't mandatory, import to DaVinci Resolve (free version), set project to "VR 180° Stereo Side-by-Side," edit, and export H.264 MP4 with "Embed VR metadata" enabled. It handles Apple Immersive Video sources well.

### 2. Example of Known-Working VR180 File to Inspect
Download this official 8K 3D VR180 sample (SBS equirectangular, ~8GB, 60fps, similar to your specs):  
[Waterfall Hike: VR Travel Video (8K 3D VR180)](https://escapevr.com/waterfall-hike-vr180-video/)  
- Direct MP4 link on the page (SFW nature scene).  
- Upload it to YouTube as a test—it triggers the VR viewer with head tracking immediately after processing.  
Inspect locally with tools below to baseline your metadata.

### 3. Verification Steps to Confirm Metadata Before Upload
Before uploading, validate the MP4 has correct ST3D (stereo=2), SV3D (layout=left-right), and EQUI (projection=equirectangular with VR180 bounds). Your current file has ST3D/SV3D but invalid EQUI (all 0s), so YouTube treats it as 2D.

#### Step 1: Basic Check with ffprobe (Built-in FFmpeg Tool)
Run:
```
ffprobe -v error -select_streams v:0 -show_entries stream_tags=projection,stereo_mode -of csv=p=0 output.mp4
```
- Expected: `equirectangular,left_right`  
If missing, metadata failed.

Full probe for warnings:
```
ffprobe -v warning -show_format -show_streams output.mp4 2>&1 | grep -i spherical
```
- Expected: No "Missing spherical video header" warning. Look for `spherical: yes` under streams.

#### Step 2: Detailed Box Inspection with Bento4 (Install via `apt install bento4` or Homebrew)
Download Bento4 (free): https://www.bento4.org/downloads/  
Run:
```
mp4dump output.mp4 | grep -A 20 -B 5 EQUI
```
- Expected EQUI box (excerpt):
  ```
  [Child of proj]: Equirectangular Projection Box (equi)
    left   : 0x40000000 (1073741824 = 0.25)
    top    : 0x00000000 (0 = 0.0)
    right  : 0xC0000000 (3221225472 = 0.75)
    bottom : 0xFFFFFFFF (4294967295 ≈ 1.0)
  ```
This confirms 180° horizontal crop (0.25–0.75). Vertical full (0–1). Also check:
```
mp4dump output.mp4 | grep -A 5 -B 5 'st3d\|sv3d'
```
- ST3D: `stereo_mode: 2` (side-by-side).  
- SV3D: `layout: 1` (left-right).

#### Step 3: Visual Test Locally
- Play in VLC (enable "Spherical" in Tools > Effects > Video > Advanced). It should show VR180 viewer with mouse-drag panning (not flat SBS).  
- Or use DEO VR (free on Quest/PC) for headset test.

If bounds are wrong, re-run the fork command.

### 4. YouTube-Specific Requirements or Gotchas
- **Recognition Time**: Basic VR playback (pan/tilt controls) available in ~1 hour post-upload. Full head-tracking VR viewer and max quality (8K/60fps) take 4–7+ days for processing, especially H.264 at your bitrate/resolution. Check video settings page for "360°/VR" badge—refresh periodically.
- **Upload Settings**: No special flags needed—upload as standard video (MP4, <128GB). Title/description optional ("VR180" helps discovery). Public/unlisted/private all process VR metadata identically; unlisted is fine for tests.
- **Container/Codec Gotchas**:
  - MP4 only (no MOV for faster processing—YouTube prefers MP4 for H.264).
  - H.264 must be Baseline/Main profile (libx264 default is fine; check with `ffprobe -v quiet -select_streams v:0 -show_entries stream=profile output.mp4`—avoid High if issues).
  - Bitrate: Aim 100–200 Mbps for 8K/60fps to avoid quality drops during processing.
  - No audio metadata needed unless spatial (your source may have it from .aivu—preserve with `-c:a copy`).
- **Common Pitfalls**:
  - Initial upload shows flat SBS—wait for processing; don't re-upload.
  - If still 2D after 24h, metadata failed (re-verify EQUI bounds).
  - YouTube ignores V1 metadata (your `--v2` is correct, but fork uses V2 by default).
  - High-res (your 8640×4320) may trigger "HD only" initially—patience.
  - Test upload unlisted first; if VR works, republish public.

This workflow should get your videos into the VR180 player with head tracking. If the fork errors (e.g., Python 3.6+ required), fall back to Resolve export. Let me know outputs from verification for troubleshooting.