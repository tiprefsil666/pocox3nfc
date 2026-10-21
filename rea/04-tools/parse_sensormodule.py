#!/usr/bin/env python3
"""Parse a QTI Chromatix sensormodule blob.

The blobs under vendor/lib64/camera/com.qti.sensormodule.*.bin carry the
vendor camera configuration: the sensor's power-up sequence, the register
addresses, the lane assignment, the actuator parameters and the resolution
tables.  They are the reference the mainline drivers are written against.

The file format is the "QTI Chromatix Header" with a "Parameter Parser"
section.  The layout that this tool reads was recovered by inspection of the
bytes; the notes in surya-pmos/docs/camera.es.md describe the findings it
supports.

Container layout (little-endian):

  0x000  char[24]   magic, "QTI Chromatix Header"
  0x018  u32        header size
  0x020  u16        version fields
  0x028  char[40]   parser name, "Parameter Parser V1.3.2 (1811291228)"
  0x098  u32        offset of the section table
  0x0a0  u64[]      section table: (offset, size, id) triples

  The tag directory follows, as a flat list of entries 0x48 bytes apart.
  The first entry starts at the offset the section table gives:

      +0x00  u64      tag id
      +0x08  char[24] name
      +0x18  u64      parent id (0 for a top-level tag)
      +0x20  u64      tag type (1 = container, 0 = leaf)
      +0x28  u64      child count (0xffffffff for a leaf)
      +0x30  u64      payload offset, relative to the payload base
      +0x38  u64      payload size
      +0x40  u64      tag id, sequential

  The payloads follow the directory, packed in directory order, each one
  exactly as large as its entry says.

  A payload is a sequence of *values*.  A value is a string, a number or a
  reference to another tag.  The parser below decodes the ones that matter
  for the camera work:

    "name"-type payloads   a string
    "regSetting"           a list of (key id, value id) records
    "registerData"         a register table

Usage:
  parse_sensormodule.py <blob>                 summary of every tag
  parse_sensormodule.py <blob> --tree          the tag tree
  parse_sensormodule.py <blob> --tag NAME      one tag, fully decoded
  parse_sensormodule.py <blob> --json          machine-readable output
  parse_sensormodule.py <blob> -v              decode the payloads too
"""
import argparse
import json
import struct
import sys

MAGIC = b"QTI Chromatix Header"
TAG_ENTRY_SIZE = 0x48
TAG_NAME_OFF = 0x08
TAG_NAME_LEN = 0x18
TAG_PARENT_OFF = 0x20
TAG_TYPE_OFF = 0x28
TAG_CHILDREN_OFF = 0x30
TAG_OFFSET_OFF = 0x38
TAG_SIZE_OFF = 0x40


# Tags whose payload is a plain string.
STRING_TAGS = ("sensorName", "moduleName", "eepromName", "flashName",
               "PDAFName", "lensName")


def u16(d, o):
    return struct.unpack_from("<H", d, o)[0]


def u32(d, o):
    return struct.unpack_from("<I", d, o)[0]


def u64(d, o):
    return struct.unpack_from("<Q", d, o)[0]


def cstr(d, o, maxlen=64):
    end = d.find(b"\x00", o, o + maxlen)
    if end < 0:
        end = o + maxlen
    return d[o:end].decode("latin-1")


class Tag:
    """One entry of the blob's tag directory."""

    __slots__ = ("name", "entry_offset", "payload_offset", "payload_size",
                 "tag_id", "parent_id", "children", "type")

    def __init__(self, name, entry_offset, payload_offset, payload_size,
                 tag_id, parent_id, children, type_):
        self.name = name
        self.entry_offset = entry_offset
        self.payload_offset = payload_offset
        self.payload_size = payload_size
        self.tag_id = tag_id
        self.parent_id = parent_id
        self.children = children
        self.type = type_

    def to_dict(self):
        return {
            "name": self.name,
            "payload_offset": self.payload_offset,
            "payload_size": self.payload_size,
            "id": self.tag_id,
            "parent": self.parent_id,
            "children": self.children,
            "type": self.type,
        }


def parse_header(d):
    if not d.startswith(MAGIC):
        raise SystemExit("not a QTI Chromatix header")
    return {
        "magic": cstr(d, 0, 24),
        "header_size": u32(d, 0x18),
        "version": [u16(d, 0x20), u16(d, 0x22)],
        "parser": cstr(d, 0x28, 40),
        "section_table_offset": u32(d, 0x98),
        "first_tag": u64(d, 0xA8),
        "payload_base": u64(d, 0xC0),
    }


def parse_tags(d, hdr):
    """Walk the tag directory and assign each tag its payload.

    The directory is a flat list of 0x48-byte entries.  It ends at the first
    entry whose name is empty or 0xff-filled.  The payloads follow the
    directory, packed in the same order, each exactly as large as the entry
    declares.  The offsets in the directory are relative to that base.
    """
    off = hdr["first_tag"]
    tags = []
    while off + TAG_ENTRY_SIZE <= len(d):
        raw = d[off:off + TAG_NAME_LEN]
        if not raw[0] or raw[0] == 0xFF:
            break
        name = cstr(d, off + TAG_NAME_OFF, TAG_NAME_LEN)
        if not name:
            break
        tags.append(Tag(
            name=name,
            entry_offset=off,
            payload_offset=0,
            payload_size=u64(d, off + TAG_SIZE_OFF),
            tag_id=u64(d, off),
            parent_id=u64(d, off + TAG_PARENT_OFF),
            children=u64(d, off + TAG_CHILDREN_OFF),
            type_=u64(d, off + TAG_TYPE_OFF),
        ))
        off += TAG_ENTRY_SIZE

    # The payload base is the start of the string block, which the section
    # table gives as the second block.
    base = u64(d, 0xC0)
    for t in tags:
        t.payload_offset = base + u64(d, t.entry_offset + TAG_OFFSET_OFF)
    return tags


def decode_string(d, tag):
    """Decode a string payload.

    A string payload is the string itself, NUL-padded.  It may be preceded
    by a u64 (the id of the next tag in the chain), so the string is taken
    from the first printable run rather than from offset 0.
    """
    off = tag.payload_offset
    if off >= len(d):
        return ""
    raw = d[off:off + min(tag.payload_size, 256)]
    # The string is the longest printable run in the payload; the leading
    # bytes are the id of the next tag in the chain.
    best_start, best_len = 0, 0
    start = None
    for i, b in enumerate(raw):
        if 32 <= b < 127:
            if start is None:
                start = i
        else:
            if start is not None and i - start > best_len:
                best_start, best_len = start, i - start
            start = None
    if start is not None and len(raw) - start > best_len:
        best_start, best_len = start, len(raw) - start
    return raw[best_start:best_start + best_len].decode("latin-1")


def decode_register_table(d, tag):
    """Decode a register table into a list of (addr, value).

    The table is a run of 8-byte entries:

        u32      register address
        u32      value

    The table's *addresses* live in the payload pool next to the section
    that names it, not in the section's own payload: a registerData section
    holds the count and a list of offsets, and the entries themselves are
    elsewhere in the pool.  This function therefore only decodes a section
    that already holds the entries; the pool walk is in dump_reg_table.py.
    """
    out = []
    off = tag.payload_offset
    end = off + tag.payload_size
    while off + 8 <= end:
        addr = u32(d, off)
        value = u32(d, off + 4)
        if not (0x0100 <= addr <= 0x7FFF):
            break
        out.append((addr, value))
        off += 8
    return out


def decode_reg_setting(d, tag):
    """Decode a 'regSetting' payload into (key id, value id) records."""
    out = []
    off = tag.payload_offset
    end = off + tag.payload_size
    while off + 16 <= end:
        out.append((u64(d, off), u64(d, off + 8)))
        off += 16
    return out


def show_tag(d, tag, idmap, verbose=False):
    print("%-24s id=%-5d parent=%-5d payload=0x%-7x size=%d"
          % (tag.name, tag.tag_id, tag.parent_id,
             tag.payload_offset, tag.payload_size))
    if not verbose:
        return
    if tag.payload_size == 0 or tag.payload_offset + tag.payload_size > len(d):
        return
    payload = d[tag.payload_offset:tag.payload_offset + min(tag.payload_size, 48)]
    print("    first bytes: %s" % payload.hex(" "))

    if tag.name in STRING_TAGS:
        print("    value: %r" % decode_string(d, tag))
    elif "regSetting" in tag.name:
        recs = decode_reg_setting(d, tag)
        print("    %d records; first few:" % len(recs))
        for k, v in recs[:12]:
            print("      %-22s -> %-22s"
                  % (idmap.get(k, "id_%d" % k), idmap.get(v, "0x%x" % v)))
    elif "registerData" in tag.name:
        regs = decode_register_table(d, tag)
        print("    %d registers:" % len(regs))
        for a, v in regs[:16]:
            print("      0x%04x = 0x%04x" % (a, v))
        if len(regs) > 16:
            print("      ... %d more" % (len(regs) - 16))


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("blob")
    ap.add_argument("--tree", action="store_true", help="print the tag tree")
    ap.add_argument("--tag", help="decode only this tag")
    ap.add_argument("--json", action="store_true", help="machine-readable output")
    ap.add_argument("--verbose", "-v", action="store_true")
    args = ap.parse_args()

    d = open(args.blob, "rb").read()
    hdr = parse_header(d)
    tags = parse_tags(d, hdr)
    idmap = {t.tag_id: t.name for t in tags}

    if args.json:
        print(json.dumps({
            "file": args.blob,
            "size": len(d),
            "header": hdr,
            "tags": [t.to_dict() for t in tags],
        }, indent=1))
        return 0

    print("file  : %s (%d bytes)" % (args.blob, len(d)))
    print("header: %s, parser %r" % (hdr["magic"], hdr["parser"]))
    print("tags  : %d" % len(tags))
    print()

    if args.tag:
        for t in tags:
            if t.name == args.tag:
                show_tag(d, t, idmap, args.verbose)
                return 0
        print("tag %r not found" % args.tag)
        return 1

    for t in tags:
        if args.tree:
            print("%-24s id=%-5d parent=%-5d size=%d"
                  % (t.name, t.tag_id, t.parent_id, t.payload_size))
        else:
            show_tag(d, t, idmap, args.verbose)
    return 0


if __name__ == "__main__":
    sys.exit(main())
