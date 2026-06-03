#!/usr/bin/env python3
"""从 Charles .chls 会话文件中提取 multipart 里 application/x-gzip 的原始数据。"""

from __future__ import annotations

import gzip
import re
import struct
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable
from urllib.parse import parse_qs


GZIP_MAGIC = b"\x1f\x8b\x08"
GZIP_PART_HEADER = b"Content-Type: application/x-gzip\r\n\r\n"


@dataclass(frozen=True)
class GzipPart:
    """multipart 中 gzip 字段及其解压结果。"""

    gzip_raw: bytes
    decompressed: bytes
    source_offset: int | None = None

    @property
    def decompressed_text(self) -> str:
        return self.decompressed.decode("utf-8", errors="replace")

    @property
    def form_fields(self) -> dict[str, list[str]]:
        """解压后为 application/x-www-form-urlencoded 时解析为字典。"""
        return parse_qs(self.decompressed_text, keep_blank_values=True)


def read_java_byte_arrays(data: bytes) -> Iterable[tuple[int, bytes]]:
    """扫描 Java 序列化流中的 [B 字节数组（Charles requestBody 等）。"""
    marker = b"ur\x00\x02[B\xac\xf3\x17\xf8\x06\x08T\xe0\x02\x00\x00xp"
    pos = 0
    while True:
        idx = data.find(marker, pos)
        if idx < 0:
            break
        start = idx + len(marker)
        if start + 4 > len(data):
            break
        (length,) = struct.unpack(">i", data[start : start + 4])
        payload_start = start + 4
        payload_end = payload_start + length
        if payload_end > len(data) or length < 0:
            pos = start
            continue
        yield payload_start, data[payload_start:payload_end]
        pos = payload_end


def extract_gzip_from_multipart(body: bytes) -> bytes | None:
    """从完整 multipart 请求体中取出 application/x-gzip 段的压缩字节。"""
    match = re.search(
        rb'Content-Disposition:[^\r\n]*name="file"[^\r\n]*\r\n'
        rb"Content-Type:\s*application/x-gzip\r\n\r\n",
        body,
        re.IGNORECASE,
    )
    if not match:
        match = re.search(
            rb"Content-Type:\s*application/x-gzip\r\n\r\n",
            body,
            re.IGNORECASE,
        )
    if not match:
        return None

    gzip_start = match.end()
    end = body.find(b"\r\n--", gzip_start)
    if end < 0:
        return None
    return body[gzip_start:end]


def extract_gzip_by_marker(blob: bytes) -> list[GzipPart]:
    """在任意二进制块（含 .chls 整文件）中按 Content-Type 标记定位 gzip 段。"""
    parts: list[GzipPart] = []
    search_from = 0
    while True:
        idx = blob.find(GZIP_PART_HEADER, search_from)
        if idx < 0:
            break
        gzip_start = idx + len(GZIP_PART_HEADER)
        if not blob.startswith(GZIP_MAGIC, gzip_start):
            search_from = gzip_start
            continue
        end = blob.find(b"\r\n--", gzip_start)
        if end < 0:
            break
        raw = blob[gzip_start:end]
        try:
            decompressed = gzip.decompress(raw)
        except gzip.BadGzipFile:
            search_from = gzip_start + 1
            continue
        parts.append(GzipPart(gzip_raw=raw, decompressed=decompressed, source_offset=idx))
        search_from = end
    return parts


def extract_from_chls(path: str | Path) -> list[GzipPart]:
    """
    解析 Charles .chls 文件，返回所有 application/x-gzip multipart 字段。

    优先从 Java 序列化里的 requestBody 字节数组解析；若无则回退到全文件扫描。
    """
    data = Path(path).read_bytes()
    seen: set[bytes] = set()
    parts: list[GzipPart] = []

    for _offset, body in read_java_byte_arrays(data):
        if b"multipart/form-data" not in body and GZIP_PART_HEADER not in body:
            continue
        raw = extract_gzip_from_multipart(body)
        if raw is None or raw in seen:
            continue
        seen.add(raw)
        parts.append(
            GzipPart(
                gzip_raw=raw,
                decompressed=gzip.decompress(raw),
                source_offset=None,
            )
        )

    if parts:
        return parts

    return extract_gzip_by_marker(data)


def parts_to_json(parts: list[GzipPart]) -> dict:
    import base64

    return {
        "parts": [
            {
                "index": i,
                "gzip_size": len(part.gzip_raw),
                "decompressed_text": part.decompressed_text,
                "fields": {
                    k: v[0] if len(v) == 1 else v
                    for k, v in part.form_fields.items()
                },
                "gzip_base64": base64.b64encode(part.gzip_raw).decode("ascii"),
            }
            for i, part in enumerate(parts)
        ]
    }


def main() -> None:
    import argparse
    import json
    import sys

    parser = argparse.ArgumentParser(description="从 Charles .chls 提取 application/x-gzip 原始数据")
    parser.add_argument("chls_file", help=".chls 会话文件路径")
    parser.add_argument(
        "--output",
        choices=["gzip", "raw", "text", "fields"],
        default="text",
        help="gzip=仅压缩字节; raw=解压后字节; text=解压后文本; fields=解析为表单 JSON",
    )
    parser.add_argument("-o", "--out-file", help="写入文件而非 stdout")
    parser.add_argument("--index", type=int, default=0, help="多个匹配时选择第几个（默认 0）")
    parser.add_argument("--json", action="store_true", help="输出 JSON（供 macOS App 调用）")
    args = parser.parse_args()

    parts = extract_from_chls(args.chls_file)
    if not parts:
        print("未找到 application/x-gzip 段", file=sys.stderr)
        sys.exit(1)

    if args.json:
        print(json.dumps(parts_to_json(parts), ensure_ascii=False))
        return

    if args.index >= len(parts):
        print(f"只有 {len(parts)} 个 gzip 段，index={args.index} 越界", file=sys.stderr)
        sys.exit(1)

    part = parts[args.index]
    if args.output == "gzip":
        payload: bytes | str = part.gzip_raw
    elif args.output == "raw":
        payload = part.decompressed
    elif args.output == "fields":
        payload = json.dumps(
            {k: v[0] if len(v) == 1 else v for k, v in part.form_fields.items()},
            ensure_ascii=False,
            indent=2,
        )
    else:
        payload = part.decompressed_text

    if args.out_file:
        mode = "wb" if isinstance(payload, bytes) else "w"
        with open(args.out_file, mode) as f:
            f.write(payload)
    elif isinstance(payload, bytes):
        sys.stdout.buffer.write(payload)
    else:
        print(payload)


if __name__ == "__main__":
    main()
