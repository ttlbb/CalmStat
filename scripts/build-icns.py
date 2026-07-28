#!/usr/bin/env python3

import struct
import sys
from pathlib import Path


CHUNKS = (
    ("icp4", "icon_16x16.png"),
    ("icp5", "icon_32x32.png"),
    ("icp6", "icon_32x32@2x.png"),
    ("ic07", "icon_128x128.png"),
    ("ic08", "icon_256x256.png"),
    ("ic09", "icon_512x512.png"),
    ("ic10", "icon_512x512@2x.png"),
    ("ic11", "icon_16x16@2x.png"),
    ("ic12", "icon_32x32@2x.png"),
    ("ic13", "icon_128x128@2x.png"),
    ("ic14", "icon_256x256@2x.png"),
)


def main() -> int:
    if len(sys.argv) != 3:
        print("用法：build-icns.py <输入.iconset> <输出.icns>", file=sys.stderr)
        return 2

    iconset_path = Path(sys.argv[1])
    output_path = Path(sys.argv[2])
    chunks: list[bytes] = []

    for chunk_type, filename in CHUNKS:
        image_data = (iconset_path / filename).read_bytes()
        chunk = chunk_type.encode("ascii") + struct.pack(">I", len(image_data) + 8) + image_data
        chunks.append(chunk)

    payload = b"".join(chunks)
    output_path.write_bytes(b"icns" + struct.pack(">I", len(payload) + 8) + payload)
    print(f"已生成：{output_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
