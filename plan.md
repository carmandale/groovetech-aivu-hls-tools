Here you go — a single-file Swift CLI that takes your .aivu, makes an HLS package, patches the master for immersive playback (REQ-VIDEO-LAYOUT + optional venue AIME reference), and validates if Apple’s tools are present. It’s already in the canvas as aivu2hls.swift.

How to use it
	1.	save the file
	2.	make it executable
	3.	run it on your .aivu

# 1) Save from the canvas as aivu2hls.swift (or copy to that name)
# 2) Make executable
chmod +x aivu2hls.swift

# 3) Run it
./aivu2hls.swift \
  -i /path/to/movie.aivu \
  -o /path/to/hls_out \
  --aime /path/to/venue.aime \
  -n my_stream \
  -d 6.0 \
  -r 25000000,50000000,100000000 \
  --layout "CH=STEREO/PROJ=AIV" \
  --video-range PQ

What it does
	•	Prefers Apple’s HLS tools if installed (mediafilesegmenter, variantplaylistcreator, mediastreamvalidator).
	•	Falls back to AVFoundation (AVAssetExportPresetAppleHLS) when HLS tools aren’t present.
	•	Keeps immersive metadata and patches master:
	•	Ensures #EXT-X-VERSION:12
	•	Adds REQ-VIDEO-LAYOUT="CH=STEREO/PROJ=AIV"
	•	Adds #EXT-X-IMMERSIVE-VIDEO:URI="venue.aime" when you pass --aime
	•	Adds VIDEO-RANGE=PQ unless you override
	•	Copies your AIME file next to the playlists (so Vision Pro can project correctly).
	•	Validates with mediastreamvalidator if available.

Notes / knobs
	•	Bitrate ladder: -r accepts comma-separated BANDWIDTH values (bps). Defaults to 25e6,50e6,100e6.
	•	Segment duration: -d seconds (default 6.0).
	•	Projection / layout: --layout lets you change the REQ-VIDEO-LAYOUT value (default CH=STEREO/PROJ=AIV).
	•	HDR signaling: --video-range PQ by default; change or remove as needed.
	•	APAC audio: the tool doesn’t transcode audio; it preserves playlists and lets you wire up your APAC alternate‐audio. (If your export already contains an HLS audio playlist, it remains available; otherwise add an EXT-X-MEDIA entry as needed.)

Expected output
	•	hls_out/
	•	my_stream.m3u8 (master; patched)
	•	*.m3u8 media playlists + .m4s/.mp4 segments
	•	venue.aime (copied when --aime is supplied)

If you want me to add Nginx/Apache MIME snippets or auto-emit a sample APAC EXT-X-MEDIA line tailored to your audio, say the word and I’ll wire it in.