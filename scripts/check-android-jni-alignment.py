#!/usr/bin/env python3
"""Check 64-bit JNI ELF LOAD alignment after an Android native build.

Usage: python3 scripts/check-android-jni-alignment.py path/to/libopuslib-jni.so [...]
"""

import argparse
import struct
from pathlib import Path

MIN_ALIGNMENT = 16384


def check_library(path: Path) -> None:
    if path.name != "libopuslib-jni.so":
        raise ValueError("expected libopuslib-jni.so")
    data = path.read_bytes()
    if len(data) < 64 or data[:4] != b"\x7fELF" or data[4] != 2:
        raise ValueError("expected a 64-bit ELF shared library")
    if data[5] not in (1, 2):
        raise ValueError("unknown ELF byte order")

    endian = "<" if data[5] == 1 else ">"
    elf_type, machine = struct.unpack_from(endian + "HH", data, 16)
    if elf_type != 3 or machine not in (62, 183):
        raise ValueError("expected an AArch64 or x86_64 ELF shared library")
    program_offset = struct.unpack_from(endian + "Q", data, 32)[0]
    entry_size, entry_count = struct.unpack_from(endian + "HH", data, 54)
    if entry_size < 56 or program_offset + entry_size * entry_count > len(data):
        raise ValueError("invalid ELF program-header table")

    load_alignments = [
        struct.unpack_from(endian + "Q", data, program_offset + index * entry_size + 48)[0]
        for index in range(entry_count)
        if struct.unpack_from(endian + "I", data, program_offset + index * entry_size)[0] == 1
    ]
    if not load_alignments or min(load_alignments) < MIN_ALIGNMENT:
        raise ValueError(f"LOAD alignment {load_alignments}, requires at least {MIN_ALIGNMENT}")
    print(f"PASS {path}: LOAD alignment {load_alignments}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("libraries", nargs="+", type=Path)
    args = parser.parse_args()
    failed = False
    for path in args.libraries:
        try:
            check_library(path)
        except (OSError, ValueError, struct.error) as error:
            print(f"FAIL {path}: {error}")
            failed = True
    if failed:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
