.PHONY: all kitten nobrainer clean

BUILD_DIR := build
SEGMENT_DURATION ?= 6.0
BITRATES ?= 25000000,50000000,100000000
LAYOUT ?= CH=STEREO/PROJ=AIV
VIDEO_RANGE ?= PQ

all: kitten

kitten:
	mkdir -p "$(BUILD_DIR)/kitten"
	./aivu2hls.swift \
		-i "media/Kitten.aivu" \
		-o "$(BUILD_DIR)/kitten" \
		-n kitten \
		-d $(SEGMENT_DURATION) \
		-r $(BITRATES) \
		--layout "$(LAYOUT)" \
		--video-range "$(VIDEO_RANGE)"

nobrainer:
	mkdir -p "$(BUILD_DIR)/nobrainer"
	./aivu2hls.swift \
		-i "media/NoBrainer.aivu" \
		-o "$(BUILD_DIR)/nobrainer" \
		-n nobrainer \
		-d $(SEGMENT_DURATION) \
		-r $(BITRATES) \
		--layout "$(LAYOUT)" \
		--video-range "$(VIDEO_RANGE)"

clean:
	rm -rf "$(BUILD_DIR)"
