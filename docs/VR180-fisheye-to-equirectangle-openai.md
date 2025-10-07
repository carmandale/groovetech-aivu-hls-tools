Short answer: yes—but only if your SBS file is already equirectangular per-eye. Apple Immersive (.aivu) frames are stored in fisheye (“lens space”) for each eye; URSA Cine Immersive captures dual fisheye, and Apple’s pipeline decodes this lens-space projection to the viewable format. If your intermediate 8640×4320 SBS is still fisheye per eye, you must first reproject fisheye → equirectangular (per eye) before injecting VR180 metadata.  ￼

Here’s how to handle both cases:

A) Your SBS is still fisheye (lens-space) → convert to equirect first

Use FFmpeg’s v360 filter (it supports fisheye/dual-fisheye to equirect). Example pipelines other creators use for dual-fisheye → equirect SBS 180:  ￼

# Input: SBS fisheye (each eye is fisheye). Output: SBS equirect 8640x4320 (4320x4320 per eye)
ffmpeg -i sbs_fisheye.mp4 -vf \
"v360=input=fisheye:in_stereo=sbs:out_stereo=sbs:output=equirect:h_fov=180:v_fov=180:w=8640:h=4320:yaw=0:pitch=0:roll=0,setsar=1,setdar=2" \
-r 60 -c:v libx264 -pix_fmt yuv420p -crf 12 -preset slow -movflags +faststart sbs_equi.mp4

Notes:
	•	If your source is dual-fisheye in one frame (two circular images), use input=dual_fisheye (or split/crop first), then map to output=equirect. Tuning h_fov, v_fov, yaw/pitch/roll, and lens center may be needed per camera; the v360 filter is made for this reprojection.  ￼
	•	Real-world example command from a Canon dual-fisheye workflow (community-tested):
... -filter:v "stereo3d=sbsr:sbsl,v360=input=fisheye:in_stereo=sbs:out_stereo=sbs:output=equirect:h_fov=180,setdar=2" ...  ￼
	•	If you’re using Resolve 20.1+ on URSA Cine Immersive footage, Blackmagic’s pipeline can output a “spatial video” SBS that’s already flattened (not fisheye). If you export that, you can skip the v360 step and go straight to metadata injection.  ￼

B) Your SBS is already equirectangular per-eye → inject VR180 metadata

When each eye is 4320×4320 equirect in a single 8640×4320 frame, inject VR180 metadata so YouTube knows it’s stereo 180 (not flat SBS):

python3 -m spatialmedia -i --v2 \
  --stereo=left-right \
  --projection=equirectangular \
  --crop 4320:4320:8640:4320:2160:0 \
  sbs_equi.mp4 sbs_equi_vr180.mp4

Why these flags:
	•	--stereo=left-right writes the st3d atom (StereoMode=2, SBS). YouTube requires this for 3D detection.  ￼
	•	--projection=equirectangular --v2 writes Spherical Video V2 (sv3d) with projection info.
	•	--crop 4320:4320:8640:4320:2160:0 tells YouTube the video covers the front 180×180° of a 360×180 sphere (centered), which is how VR180 is represented in metadata (equirect + front-half crop). This is the standard way VR180 is tagged; older Google tools did the same via cropped equirect bounds.  ￼

Quick verification checklist (pre-upload)
	•	ffprobe: confirm stereo & spherical tags; no “Missing spherical video header” warnings after injection. (Before injection, ffprobe often shows that warning.)
	•	Atom dump (MP4Box/mp4dump): check for st3d (stereo mode = side-by-side) and sv3d (equirect with non-zero bounds indicating 180° front).  ￼
	•	Sanity test in a VR video player (Skybox/DeoVR): should auto-detect 180 3D if metadata is right.

YouTube processing gotchas
	•	It may show flat SBS right after upload. For high-res VR, processing can take from minutes up to hours before VR180 playback appears with “spherical” quality tiers (e.g., 2160s/4320s). Unlisted vs public doesn’t change processing—keep it Unlisted until VR playback appears.  ￼

⸻

TL;DR
	•	If your 8640×4320 SBS is still fisheye per-eye, first run FFmpeg v360 to map fisheye → equirectangular (per eye).  ￼
	•	Then inject stereo + 180° equirect crop metadata with Spatial Media (command above). This is what makes YouTube flip to the VR180 viewer instead of showing a flat SBS frame.  ￼

If you want, I can wrap this into a small Python CLI (ffmpeg + spatialmedia subprocess) that:
	1.	Detects whether frames are fisheye or equirect (simple heuristic on circular content / metadata),
	2.	Runs the appropriate v360 reprojection when needed,
	3.	Injects VR180 metadata, and
	4.	Runs ffprobe to output a pass/fail report.