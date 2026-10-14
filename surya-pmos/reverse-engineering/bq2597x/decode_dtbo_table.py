#!/usr/bin/env python3
"""Index Android DTBO table entries containing the Surya BQ2597x node."""
import argparse
import csv
import hashlib
import struct
from pathlib import Path

MAGIC = 0xD7B7AB1E
NEEDLE = b"bq2597x-charger@65"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("dtbo", type=Path)
    parser.add_argument("csv_out", type=Path)
    args = parser.parse_args()
    data = args.dtbo.read_bytes()
    magic, total, header_size, entry_size, count, entries_offset, page_size, version = struct.unpack_from(">8I", data)
    if magic != MAGIC:
        raise SystemExit(f"unexpected DT table magic: {magic:#x}")
    if total > len(data) or entries_offset + count * entry_size > total or entry_size < 32:
        raise SystemExit("invalid DT table bounds")
    rows = []
    for index in range(count):
        pos = entries_offset + index * entry_size
        size, offset, ident, revision, *custom = struct.unpack_from(">8I", data, pos)
        end = offset + size
        if end > total:
            raise SystemExit(f"entry {index} exceeds declared table size")
        blob = data[offset:end]
        if NEEDLE in blob:
            rows.append([index, offset, size, ident, revision, hashlib.sha256(blob).hexdigest()])
    args.csv_out.parent.mkdir(parents=True, exist_ok=True)
    with args.csv_out.open("w", newline="") as stream:
        writer = csv.writer(stream)
        writer.writerow(["dtbo_entry_index_zero_based", "offset_bytes", "entry_size_bytes", "id", "revision", "entry_sha256"])
        writer.writerows(rows)
    print(f"table: count={count}, page_size={page_size}, header={header_size}, version={version}")
    print(f"matching entries: {len(rows)} -> {args.csv_out}")


if __name__ == "__main__":
    main()
