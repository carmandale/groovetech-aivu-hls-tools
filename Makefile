.PHONY: all kitten nobrainer clean

BUILD_DIR := build
PYTHON ?= python3
AIME_EXTRACTOR := tools/extract_aime.py
KIT_AIME := $(BUILD_DIR)/kitten.venue.aime
NOBRAINER_AIME := $(BUILD_DIR)/nobrainer.venue.aime
SEGMENT_DURATION ?= 6.0
BITRATES ?= 25000000,50000000,100000000
LAYOUT ?= CH-STEREO/PACK-NONE/PROJ-AIV
VIDEO_RANGE ?= PQ

all: kitten

kitten:
	mkdir -p "$(BUILD_DIR)/kitten"
	$(PYTHON) "$(AIME_EXTRACTOR)" "media/Kitten.aivu" "$(KIT_AIME)" --force
	./aivu2hls.swift \
		-i "media/Kitten.aivu" \
		-o "$(BUILD_DIR)/kitten" \
		-n kitten \
		-d $(SEGMENT_DURATION) \
		-r $(BITRATES) \
		--layout "$(LAYOUT)" \
		--video-range "$(VIDEO_RANGE)" \
		--aime "$(KIT_AIME)"

nobrainer:
	mkdir -p "$(BUILD_DIR)/nobrainer"
	$(PYTHON) "$(AIME_EXTRACTOR)" "media/NoBrainer.aivu" "$(NOBRAINER_AIME)" --force
	./aivu2hls.swift \
		-i "media/NoBrainer.aivu" \
		-o "$(BUILD_DIR)/nobrainer" \
		-n nobrainer \
		-d $(SEGMENT_DURATION) \
		-r $(BITRATES) \
		--layout "$(LAYOUT)" \
		--video-range "$(VIDEO_RANGE)" \
		--aime "$(NOBRAINER_AIME)"

clean:
	rm -rf "$(BUILD_DIR)"
