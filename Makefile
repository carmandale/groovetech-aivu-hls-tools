.PHONY: all kitten nobrainer youtube clean

BUILD_DIR := build
PYTHON ?= python3
SPATIALMEDIA ?= python3 -m spatialmedia
AIME_EXTRACTOR := tools/extract_aime.py
KIT_INPUT ?= media/Kitten.aivu
NOBRAINER_INPUT ?= media/NoBrainer.aivu
KIT_AIME := $(BUILD_DIR)/kitten.venue.aime
NOBRAINER_AIME := $(BUILD_DIR)/nobrainer.venue.aime
SEGMENT_DURATION ?= 6.0
BITRATES ?= 25000000,50000000,100000000
LAYOUT ?= CH-STEREO/PACK-NONE/PROJ-AIV
VIDEO_RANGE ?= PQ

all: kitten

kitten:
	@[ -f "$(KIT_INPUT)" ] || (echo "Missing $(KIT_INPUT). Copy Kitten.aivu into media/." && exit 1)
	mkdir -p "$(BUILD_DIR)/kitten"
	$(PYTHON) "$(AIME_EXTRACTOR)" "$(KIT_INPUT)" "$(KIT_AIME)" --force
	./aivu2hls.swift \
		-i "$(KIT_INPUT)" \
		-o "$(BUILD_DIR)/kitten" \
		-n kitten \
		-d $(SEGMENT_DURATION) \
		-r $(BITRATES) \
		--layout "$(LAYOUT)" \
		--video-range "$(VIDEO_RANGE)" \
		--aime "$(KIT_AIME)"

nobrainer:
	@[ -f "$(NOBRAINER_INPUT)" ] || (echo "Missing $(NOBRAINER_INPUT). Copy NoBrainer.aivu into media/." && exit 1)
	mkdir -p "$(BUILD_DIR)/nobrainer"
	$(PYTHON) "$(AIME_EXTRACTOR)" "$(NOBRAINER_INPUT)" "$(NOBRAINER_AIME)" --force
	./aivu2hls.swift \
		-i "$(NOBRAINER_INPUT)" \
		-o "$(BUILD_DIR)/nobrainer" \
		-n nobrainer \
		-d $(SEGMENT_DURATION) \
		-r $(BITRATES) \
		--layout "$(LAYOUT)" \
		--video-range "$(VIDEO_RANGE)" \
		--aime "$(NOBRAINER_AIME)"

youtube:
	@[ "$(MOVIE)" != "" ] || (echo "Set MOVIE=<basename without extension> (e.g. MOVIE=NoBrainer)" && exit 1)
	@MOVIE_INPUT="media/$(MOVIE).aivu"; \
	 [ -f "$$MOVIE_INPUT" ] || (echo "Missing $$MOVIE_INPUT. Copy $(MOVIE).aivu into media/." && exit 1); \
	 MOVIE_LOWER=$$(echo "$(MOVIE)" | tr '[:upper:]' '[:lower:]'); \
	 YOUTUBE_RAW="$(BUILD_DIR)/$${MOVIE_LOWER}_youtube_raw.mp4"; \
	 YOUTUBE_FINAL="$(BUILD_DIR)/$${MOVIE_LOWER}_youtube.mp4"; \
	 mkdir -p "$(BUILD_DIR)"; \
	 ffmpeg -y -i "$$MOVIE_INPUT" -map 0:v:0 -map 0:a? -c copy "$$YOUTUBE_RAW"; \
	 $(SPATIALMEDIA) -i "$$YOUTUBE_RAW" -o "$$YOUTUBE_FINAL" --stereo=top-bottom --projection=equirectangular --crop 4320:2160:4320:4320:0:0; \
	 echo "YouTube-ready clip: $$YOUTUBE_FINAL"

clean:
	rm -rf "$(BUILD_DIR)"
