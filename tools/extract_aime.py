#!/usr/bin/env python3

"""Extract embedded AIME venue data from a .aivu QuickTime file."""

from __future__ import annotations

import argparse
import mmap
import struct
from pathlib import Path

PATTERN = b"\x00\x00\x00\x00\x88\x00\x00\x00"
KEY = b"com.apple.quicktime.aime-data"


def locate_descriptor(mm: mmap.mmap) -> tuple[int, int]:
    """Return (offset, length) for the embedded AIME payload."""

    key_index = mm.find(KEY)
    if key_index == -1:
        raise RuntimeError("AIME key not found in file")

    search_start = max(0, key_index - 512)
    search_end = min(len(mm), key_index + 1024)

    descriptor_start = mm.find(PATTERN, key_index, search_end)
    if descriptor_start == -1:
        descriptor_start = mm.rfind(PATTERN, search_start, key_index)
    if descriptor_start == -1:
        raise RuntimeError("Descriptor pattern not found near metadata key")

    if descriptor_start + 24 > len(mm):
        raise RuntimeError("Descriptor truncated at end of file")

    words = struct.unpack_from(">6I", mm, descriptor_start)

    # The offset/length are stored as 64-bit values left-shifted by 8 bits.
    offset_raw = (words[2] << 32) | words[3]
    length_raw = (words[4] << 32) | words[5]

    offset = offset_raw >> 8
    length = length_raw >> 8

    if offset <= 0 or length <= 0:
        raise RuntimeError("Descriptor reported non-positive offset/length")

    if offset + length > len(mm):
        raise RuntimeError("Descriptor range extends beyond file size")

    return offset, length


def extract_aime(input_path: Path, output_path: Path, force: bool) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)

    if output_path.exists() and not force:
        raise RuntimeError(f"Output file already exists: {output_path}")

    with input_path.open("rb") as handle:
        with mmap.mmap(handle.fileno(), 0, access=mmap.ACCESS_READ) as mm:
            offset, length = locate_descriptor(mm)
            payload = mm[offset : offset + length]

    output_path.write_bytes(payload)

    print(f"Extracted AIME: offset=0x{offset:x}, length={length} bytes → {output_path}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Extract embedded AIME venue data from an Apple Immersive Video file.")
    parser.add_argument("input", type=Path, help="Source .aivu QuickTime file")
    parser.add_argument("output", type=Path, help="Destination .aime file")
    parser.add_argument("--force", action="store_true", help="Overwrite the destination if it already exists")
    args = parser.parse_args()

    if not args.input.exists():
        raise SystemExit(f"Input file not found: {args.input}")

    try:
        extract_aime(args.input, args.output, force=args.force)
    except Exception as exc:  # noqa: BLE001
        raise SystemExit(f"Failed to extract AIME: {exc}") from exc


if __name__ == "__main__":
    main()
