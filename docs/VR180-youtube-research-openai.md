YouTube VR180 Metadata Injection and Verification

1. Correct Spatial Metadata for VR180 Side-by-Side Videos

For VR180 3D videos, YouTube expects spherical video metadata indicating a 180° front-facing stereoscopic format. The correct approach is to use equirectangular projection with appropriate cropping (since VR180 covers only the front half of a 360 sphere). In practice, this means:
	•	Projection type: Use equirectangular (the standard spherical format). Despite some outdated documentation suggesting “mesh” projection is required for VR180, Google’s own VR180 Creator tool actually used equirectangular with cropped bounds ￼. The equirectangular setting is correct for VR180 when combined with proper crop parameters to indicate a 180° field of view.
	•	Stereo mode: Use side-by-side (left-right) stereoscopic layout. This will inject the ST3D box with Stereo Mode = 2 (side-by-side) as needed ￼.
	•	Crop parameters: You must specify that the video frame represents only the front 180×180 degrees of the sphere. The Spatial Media tool uses a --crop w:h:full_w:full_h:left:top format, where:
	•	full_w × full_h = the full 360° equirectangular canvas size,
	•	w × h = the portion that your video covers,
	•	left, top = the offset of that portion within the full canvas.
For a VR180 video that is 8640×4320 side-by-side (i.e. each eye is 4320×4320 covering 180°×180°), the correct crop values are:
--crop 4320:4320:8640:4320:2160:0.
Explanation: Here full_w:full_h=8640:4320 represents a full 360° sphere at 8K equirectangular (because if 180° = 4320px, then 360° would be 8640px). The content w:h=4320:4320 is the front hemisphere for each eye. We set left=2160 (pixels) which crops out 25% on the left and 25% on the right – leaving the middle 50% of the sphere (180°) as the visible region ￼. top=0 since the video covers the full vertical 180°. This centers the 4320px-wide view in the front of the 8640px canvas (2160px padding on each side). These crop values correspond to left/right bounds of 0.25 in the metadata (meaning 25% of the sphere is blank on each side, leaving a 50% central region) ￼.
	•	“V2” metadata: Include the --v2 flag to use Spherical Video V2 metadata (required by YouTube for 180/360 VR). This injects the SV3D (Spherical Video V2) box with projection and cropping info. (The older V1 metadata is deprecated, though Google’s VR180 Creator used to add both V1 and V2 for compatibility ￼.)

Putting it together, the Spatial Media Metadata Injector command would be:

python3 -m spatialmedia -i --v2 \
  --stereo=left-right \
  --projection=equirectangular \
  --crop 4320:4320:8640:4320:2160:0 \
  input.mp4 output_vr180.mp4

This ensures the MP4 has the correct StereoMode (ST3D) and Spherical Video (SV3D) metadata. With these parameters, the equirectangular projection is flagged as 180° (half-spherical) due to the crop. (In your current attempt, the crop was mis-specified – causing all Equirectangular bounds to show as 0.0, which indicated an error. The above values fix that by properly indicating 180° coverage for the front hemisphere.)

Are these the right settings? Yes – equirectangular + cropping is the standard for VR180 on YouTube. In fact, Google’s own discontinued VR180 Creator tool used equirect projection with left/right bounds of ~0.25 (i.e. 180°) for VR180 videos ￼. YouTube will accept 180° videos only if they are stereo; mono 180 is not officially supported unless you duplicate it as stereo ￼. The above settings yield a stereo 180 video which YouTube recognizes.

For completeness, ensure your video dimensions are correct: 8640×4320 where left-eye is the left 4320×4320 region and right-eye is the right 4320×4320. The --stereo=left-right flag assumes exactly that layout. (If your left/right were swapped for some reason, use right-left, but normally VR180 uses left on left.) Also confirm the video’s aspect ratio matches 2:1 (which it does), since equirectangular 360 or 180 content should be 2:1 or 1:1 per-eye for a full vertical FOV.

2. Tools and Workflow for Injecting VR180 Metadata

Google’s spatial-media tool (the one you are using) does support 180/VR180 metadata, but some older versions had bugs. If you still encounter issues, consider using community-enhanced tools:
	•	VR180 Creator (Google) – a GUI tool for Mac/Win/Linux that injects VR180 metadata. Google has removed the download, but it essentially accomplished the same as above. If you can find a copy (e.g., via Archive or third-party links), it provides a simple way to tag VR180 videos correctly ￼ ￼. (It required the video to be MP4; if you got “Video dimensions must be set for v1 metadata” errors, converting to MP4 with ffmpeg -c copy often helped ￼.)
	•	Spatial Media Injector – Vargol’s fork – an open-source fork of Google’s tool specifically updated for VR180 use. This version adds convenient modes for 180. For example, you can use -m equi-mesh or -m equirectangular for VR180 without manually computing crops ￼ ￼. Vargol’s fork is designed to “fake” the metadata of Google’s VR180 cameras and has presets for full-frame SBS VR180 etc. ￼ ￼. Using this can simplify injection (and was reported to fix some metadata bugs in the original tool ￼).
	•	FFmpeg – in theory ffmpeg can pass through or set stereoscopic metadata (e.g., using -x264opts "frame-packing=3" or -metadata:s:v stereo_mode=...). However, ffmpeg cannot fully inject the spherical (180/360) VR header via simple CLI options – it can tag the video stream as 3D side-by-side, but not the 180° projection info properly ￼ ￼. There is no straightforward ffmpeg flag for “180° VR” projection metadata as of 2025. While you can encode the video with ffmpeg (ensuring high profile H.264 and correct resolution), you’ll still need to inject the VR180 metadata using a specialized tool (or a manual MP4 box editor). Some have used ffmpeg + mp4box or custom scripts to insert the sv3d/st3d boxes, but it’s much easier to use the ready-made injector.
	•	Other Tools: Adobe Premiere/Media Encoder has a “VR Video” settings checkbox where you can specify 180° stereoscopic and it will export with proper metadata ￼. Similarly, Kandao’s VR180 Studio, Mistika VR, and other VR software can inject metadata if you use them for stitching or editing. There are also free apps (e.g. “VR180 Metadata Injector” on Mac App Store ￼) that provide one-click metadata injection. If you prefer a scriptable route, the Python-based spatialmedia tool (as above) is your best bet – you can integrate it into a Python script or pipeline easily.

MP4 container requirements: YouTube prefers an MP4 container for spherical videos. Ensure the file is a standard MP4 (not MOV, which can hold the same boxes but sometimes isn’t recognized immediately – MP4 is safer for YouTube ingestion ￼). Use -movflags +faststart if you recompress with ffmpeg, so the moov atom is at the start (not strictly required, but helps YouTube begin processing sooner). The codec H.264 is acceptable up to 8640×4320 60fps, but make sure to use High Profile level 5.2 or above during encoding (ffmpeg’s libx264 will automatically choose an appropriate level for 8K – you may see level 6.0+ for 60fps 8K). YouTube will re-encode everything anyway, but providing a high-quality H.264 or H.265 can improve the upload pipeline. (You asked about YouTube’s recommended codec: H.264 is most universal. YouTube also accepts HEVC/H.265 in MP4, and even ProRes or VP9 in some cases, but H.264 High @ 8K is commonly used. Just use a high bitrate to preserve quality since YouTube will compress it again.)

Summary: The simplest workflow is: encode with ffmpeg (to get the large 8640×4320 SBS video in MP4), then inject metadata with the spatialmedia tool. This is entirely scriptable. For example, you could call the spatialmedia Python module from a script or use subprocess after ffmpeg encoding. If using Windows, the spatialmedia tool can be run via Python, or use the VR180 Creator GUI if manual. Once the metadata is in place, the MP4 is ready for upload to YouTube.

3. Verifying Metadata Before Upload

It’s wise to verify the injected metadata to avoid uploading a flat video again. Here are verification steps and tools:
	•	ffprobe (or ffmpeg): Use ffprobe to inspect the video’s metadata. A correctly tagged VR180 file will show stereo 3D and spherical tags. For example, ffprobe -hide_banner -show_streams output_vr180.mp4 should include something like stereo_mode=left_right in the video stream tags, and may list spherical projection info. Newer ffmpeg builds also print a summary in the console output – e.g. when opening the file, you might see lines mentioning Stereo 3D: side by side and Spherical Video: equirectangular, 180x180 (or similar). The key is that no “Missing spherical video header” warnings should appear. That warning you saw indicates the spherical metadata wasn’t recognized. After proper injection, that warning should disappear, and ffprobe will report a “spherical video” tag instead.
	•	Atom inspection: You can confirm the MP4 boxes using tools like MP4Box or mp4dump. For instance, running MP4Box -info output_vr180.mp4 should list an sv3d (Spherical Video V2) box and an st3d box. The sv3d box (specifically an “equirectangular projection” entry) should have non-zero bounds. If you see values like bound_left=0.25, bound_right=0.25, bound_top=0.0, bound_bottom=0.0 (in fraction of full width/height), that indicates a 180° horizontal crop (25% cropped on each side) and no vertical crop – which is correct ￼. In your previous attempt, all bounds were 0,0,0,0 which was incorrect (it essentially meant no defined view, confusing YouTube into treating it as full 360). The st3d atom should show StereoMode 2 (LR).
	•	Compare with a known-good file: If possible, obtain a short sample VR180 video that is known to work. For example, footage from a VR180 camera (Lenovo Mirage, Vuze XR, Canon RF Dual Fisheye, etc.) that has been properly injected. There are free samples available – e.g., the Canon VR180 sample on YouTube (“canon front row” demo) or community clips like EscapeVR’s 8K VR180 videos. You can download one and run ffprobe to see the metadata. A correctly tagged file will show the same patterns: presence of spherical metadata and stereo mode. (One reference: a user examining Google’s VR180 output found the raw metadata bytes for left/right bounds corresponded to 0.25 fractional, confirming the cropping ￼.)
	•	ExifTool: As a fallback, exiftool -G -a output_vr180.mp4 can sometimes show the “Spherical Video XML” (in cases where metadata is duplicated in an XMP packet). This isn’t always present, but some injectors include a spherical XMP as well. If it’s there, it should indicate 3D and 180. However, trusting the MP4 boxes via ffprobe/mp4box is sufficient.

In short, verify that both a stereoscopic tag and a spherical (projection) tag are present. YouTube specifically looks for the st3d box for 3D format and the new Spherical V2 metadata for 180 vs 360. If those are in place, your file is ready.

(On a side note: YouTube’s own documentation confirms that for 3D videos, the MP4 must contain an st3d atom (stereo mode) ￼. For VR180, it also needs the spherical data. The spatialmedia tool with --v2 handles both.)

4. YouTube Processing and Upload Considerations

Successfully injecting the metadata is step one – but YouTube’s processing is step two. Keep in mind:
	•	Processing time: After uploading, YouTube may take some time to register the video as VR/3D. Initially, the video might only show as a flat side-by-side 2D video (both eye views on screen) with normal quality labels. This is normal. For high-res VR videos, processing can take anywhere from a few minutes to 1-2 hours (or more) before the VR180 playback is enabled ￼. The video will go through additional encoding passes to generate the stereo 180° streams (YouTube creates separate projections for VR). During this time, the quality options might be limited (e.g. only up to 4K) and no VR icon is shown. Be patient – once processing finishes, you’ll see the quality options include a suffix like “2160s” or “4320s” (the “s” indicating spherical), and on desktop the player will have a pan button or VR headset icon. On mobile, the Cardboard icon will appear, etc. A Reddit user confirms that “it can take several hours… for the site to process the metadata and have the video play like a proper VR180” ￼ – so don’t assume it failed if it’s flat at first.
	•	Unlisted vs Public: It doesn’t matter for processing – YouTube will still process the VR versions for an unlisted video. Keeping it unlisted initially is a good idea so you can verify the VR playback before making it public. Once you upload, give it time, then try playing it (even unlisted) in the YouTube app or web – if the VR180 is recognized, you’ll be able to pan around and see it in stereo. If after a couple hours it’s still only showing a stitched SBS frame, the metadata might be wrong. (But typically, if st3d/sv3d are present as described, it will work.)
	•	YouTube upload settings: In the past, YouTube had a checkbox for “This video is 3D” or similar in the Video Details page. Nowadays, if the metadata is injected, YouTube auto-detects and that box is either hidden or auto-filled. You should not need to manually tag anything on YouTube’s side. Just ensure the metadata is there before uploading. (Double-check after upload in YouTube Studio: under “Video details → 360° playback”, it might list if it’s 180 or 360. You can’t edit that if metadata was present; it’s informational.)
	•	Video quality and codec: You mentioned ensuring the codec is what YouTube recommends. YouTube will transcode your 8640×4320@60 H.264 into multiple formats (including VR-specific MP4/WEBM/AV1 streams). They do support up to 8K resolution for 180/360. Since your file is H.264, YouTube will handle it (just make sure the encoder level was high enough to allow 8K – if you used a standard ffmpeg preset, it likely was). YouTube typically generates a range of qualities; for VR180, common max is “4320s” (which is 8K-equivalent for stereo 180). The labels “SD, HD, 4K” you saw earlier were because it wasn’t treated as VR – once it is, you’ll see “4K” replaced by “2160s” (or up to 4320s if they consider it 8K). This indicates the spherical versions. So in summary, use a high-quality codec for upload (H.264 High or HEVC) and let YouTube do the rest. (YouTube’s advanced specs mention using 8K for VR if possible, which you have done, and using high bitrate – e.g. ~150 Mbps for 8K30, even higher for 8K60. Your 8640×4320 60fps at ~100 Mbps should be okay, though more bitrate can preserve detail before YouTube re-encodes.)
	•	Spatial audio: Not asked, but if your video has spatial audio (ambisonics), ensure to inject that too. The spatialmedia tool can also add the audio metadata if provided with the right flags. If not, stereo audio is fine. This won’t affect visual VR tagging, but spatial audio is a nice addition for VR180 content if available.
	•	Testing playback: Once the video shows as VR, test it on multiple platforms:
	•	On a desktop browser, you should be able to click-and-drag or use WASD to look around within the 180° view. You’ll see that turning around shows black or a doubled image if you go beyond 180°, which is normal (YouTube uses a full sphere viewer even for 180 content, often mirroring or blanking the back hemisphere). The important part is you can look around front-facing.
	•	On the YouTube mobile app, you should get the gyro panorama and a Cardboard VR option. In Cardboard mode it will split into the two eye views for a phone VR headset.
	•	On a VR headset (e.g. using YouTube VR on Quest, or YouTube via SteamVR), the video will appear in stereoscopic 3D and you’ll have 180° of freedom to look left-right and up-down. This is the ultimate test that it’s recognized as VR180.

If all these work, you’ve achieved the goal – YouTube will present the video in a VR viewer with head tracking, instead of a flat double image.

5. Example & Final Checks

To solidify the workflow, here’s an example of the full process in a scriptable way:
	1.	Decode/Convert your Apple .aivu to the side-by-side 8640×4320 H.264 MP4 (using ffmpeg or Apple’s tool). Ensure the output is yuv420p, 60fps, etc., as you have.
	2.	Inject Metadata using the spatialmedia tool (as discussed). For instance, in a Python script:

import spatialmedia
spatialmedia.inject_metadata(input_file="video.mp4", output_file="video_vr180.mp4",
                             stereo_format="left-right", spherical=True, 
                             projection="equirectangular", crop="4320:4320:8640:4320:2160:0", 
                             inject_sv3d=True)

(This pseudo-code assumes the spatialmedia library functions; in practice you might call it via subprocess.)
This will create video_vr180.mp4 with the needed sv3d/st3d boxes.

	3.	Verify video_vr180.mp4:
	•	Run ffprobe or MP4Box to ensure the metadata is present (look for “Stereo: LR” and “Projection: Equirectangular 180” in output). For example, after proper injection, ffprobe will show Side data: stereo3d: side by side and no errors.
	•	You can also play the MP4 in a local VR player (Skybox VR, DeoVR, etc. on a headset or phone) – many VR video players will read the metadata and automatically play it as a 180 3D video if tagged. This is a quick sanity test before uploading.
	4.	Upload to YouTube (preferably as Unlisted).
	5.	Wait for processing. Monitor the YouTube player – when the “360°” controls appear and the double image merges into one VR view, processing is done. This might require checking after ~30-60 minutes, especially for such a high-res video.
	6.	Publish (set Public) once you confirm it’s working.

By following these steps with the correct metadata parameters, YouTube will recognize the video as VR180. The result will be that viewers see an immersive 180° 3D experience (with head-tracking or drag control), rather than a side-by-side squeezed frame.

Sources:
	•	Google’s VR180 metadata discussion, confirming equirectangular + cropped bounds for 180° ￼.
	•	Spatial Media (Vargol’s) documentation describing YouTube’s support for 180° stereo in equirectangular format ￼.
	•	YouTube Help on 3D video metadata (st3d box for side-by-side 3D) ￼.
	•	Reddit discussions from VR180 creators about processing time and tool usage ￼ ￼.
	•	StackExchange Q&A confirming use of Google’s VR180 Creator for correct metadata injection ￼.