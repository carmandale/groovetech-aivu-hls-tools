.PHONY: all kitten nobrainer dallas youtube clean

BUILD_DIR := build
PYTHON ?= python3
SPATIALMEDIA ?= PYTHONPATH=tools/spatial-media python3 -m spatialmedia
KIT_INPUT ?= media/Kitten.aivu
NOBRAINER_INPUT ?= media/NoBrainer.aivu
DALLAS_INPUT ?= media/Dallas.aivu
SEGMENT_DURATION ?= 6.0
BITRATES ?= 25000000,50000000,100000000
LAYOUT ?= CH-STEREO/PACK-NONE/PROJ-AIV
VIDEO_RANGE ?= PQ

all: kitten

kitten:
	@[ -f "$(KIT_INPUT)" ] || (echo "Missing $(KIT_INPUT). Copy Kitten.aivu into media/." && exit 1)
	mkdir -p "$(BUILD_DIR)/kitten"
	./aivu2hls.swift \
		-i "$(KIT_INPUT)" \
		-o "$(BUILD_DIR)/kitten" \
		-n kitten \
		-d $(SEGMENT_DURATION) \
		-r $(BITRATES) \
		--layout "$(LAYOUT)" \
		--video-range "$(VIDEO_RANGE)"

nobrainer:
	@[ -f "$(NOBRAINER_INPUT)" ] || (echo "Missing $(NOBRAINER_INPUT). Copy NoBrainer.aivu into media/." && exit 1)
	mkdir -p "$(BUILD_DIR)/nobrainer"
	./aivu2hls.swift \
		-i "$(NOBRAINER_INPUT)" \
		-o "$(BUILD_DIR)/nobrainer" \
		-n nobrainer \
		-d $(SEGMENT_DURATION) \
		-r $(BITRATES) \
		--layout "$(LAYOUT)" \
		--video-range "$(VIDEO_RANGE)"

dallas:
	@[ -f "$(DALLAS_INPUT)" ] || (echo "Missing $(DALLAS_INPUT). Copy Dallas.aivu into media/." && exit 1)
	mkdir -p "$(BUILD_DIR)/dallas"
	./aivu2hls.swift \
		-i "$(DALLAS_INPUT)" \
		-o "$(BUILD_DIR)/dallas" \
		-n dallas \
		-d $(SEGMENT_DURATION) \
		-r $(BITRATES) \
		--layout "$(LAYOUT)" \
		--video-range "$(VIDEO_RANGE)"

youtube:
	@[ "$(MOVIE)" != "" ] || (echo "Set MOVIE=<basename without extension> (e.g. MOVIE=NoBrainer)" && exit 1)
	@MOVIE_INPUT="media/$(MOVIE).aivu"; \
	 [ -f "$$MOVIE_INPUT" ] || (echo "Missing $$MOVIE_INPUT. Copy $(MOVIE).aivu into media/." && exit 1); \
	 MOVIE_LOWER=$$(echo "$(MOVIE)" | tr '[:upper:]' '[:lower:]'); \
	 YOUTUBE_RAW="$(BUILD_DIR)/$${MOVIE_LOWER}_youtube_sbs.mp4"; \
	 YOUTUBE_FINAL="$(BUILD_DIR)/$${MOVIE_LOWER}_youtube.mp4"; \
	 mkdir -p "$(BUILD_DIR)"; \
	 echo "Converting MV-HEVC to Side-by-Side 60fps for YouTube VR180..."; \
	 ffmpeg -y -i "$$MOVIE_INPUT" \
	   -vf "stereo3d=al:sbsl,fps=60" \
	   -c:v libx264 -preset medium -b:v 80M -maxrate 100M -bufsize 160M -pix_fmt yuv420p \
	   -c:a aac -b:a 192k \
	   "$$YOUTUBE_RAW"; \
	 echo "Injecting VR180 metadata..."; \
	 $(SPATIALMEDIA) -i --v2 --stereo=left-right --projection=equirectangular --crop 8640:4320:8640:8640:0:2160 "$$YOUTUBE_RAW" "$$YOUTUBE_FINAL"; \
	 rm -f "$$YOUTUBE_RAW"; \
	 echo "YouTube-ready VR180 clip: $$YOUTUBE_FINAL"

clean:
	rm -rf "$(BUILD_DIR)"
