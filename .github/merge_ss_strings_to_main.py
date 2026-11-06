#!/usr/bin/env python3
"""Merge the Chinese SideStore Localizable.strings into the main
LiveContainer.app bundle (zh-Hans), so SideStore code strings resolve
even if the lookup uses the main bundle instead of the framework bundle.

- Source: SideStore-src/AltStore/zh-Hans.lproj/Localizable.strings
  (UTF-16 OpenStep text, maintained in this repo).
- Target: Payload/LiveContainer.app/zh-Hans.lproj/Localizable.strings
  (binary plist produced by the LiveContainer archive).
- LiveContainer's own keys win on collision (there are currently none:
  LC keys are all namespaced lc.*).
- Never fails the build: on any error the original target file is
  restored and the script exits 0 with a loud warning, so the IPA is
  still produced with framework-only strings.
"""
import plistlib
import re
import shutil
import sys
from pathlib import Path

SRC = Path("SideStore-src/AltStore/zh-Hans.lproj/Localizable.strings")
DST = Path("Payload/LiveContainer.app/zh-Hans.lproj/Localizable.strings")


def canon(s):
    """OpenStep .strings spelling -> canonical string."""
    out = []
    i = 0
    while i < len(s):
        if s[i] == "\\" and i + 1 < len(s):
            nxt = s[i + 1]
            if nxt == "n":
                out.append("\n")
                i += 2
            elif nxt == '"':
                out.append('"')
                i += 2
            elif nxt == "\\":
                out.append("\\")
                i += 2
            elif nxt == "t":
                out.append("\t")
                i += 2
            else:
                out.append(s[i : i + 2])
                i += 2
        else:
            out.append(s[i])
            i += 1
    return "".join(out)


def parse_openstep_strings(path):
    text = path.read_bytes().decode("utf-16")
    entries = {}
    for m in re.finditer(
        r'"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;', text
    ):
        entries[canon(m.group(1))] = canon(m.group(2))
    return entries


def main():
    if not SRC.is_file():
        print(f"MERGE-STRINGS: SKIP source not found: {SRC}")
        return 0
    if not DST.is_file():
        print(f"MERGE-STRINGS: SKIP target not found: {DST}")
        return 0
    backup = DST.with_suffix(".strings.bak")
    try:
        ss = parse_openstep_strings(SRC)
        if len(ss) < 1000:
            raise ValueError(f"source has only {len(ss)} entries, refusing")
        with open(DST, "rb") as f:
            main_dict = plistlib.load(f)
        orig = dict(main_dict)
        added = 0
        for k, v in ss.items():
            if k not in main_dict:
                main_dict[k] = v
                added += 1
        shutil.copyfile(DST, backup)
        with open(DST, "wb") as f:
            plistlib.dump(main_dict, f, fmt=plistlib.FMT_BINARY)
        # verify
        with open(DST, "rb") as f:
            check = plistlib.load(f)
        assert len(check) == len(orig) + added, "count mismatch after merge"
        for k, v in orig.items():
            assert check.get(k) == v, f"original key changed: {k!r}"
        for probe in (
            "Registered Devices (%lld)",
            "Network Connectivity",
            "On-Device Anisette",
        ):
            assert probe in check, f"probe missing: {probe!r}"
        backup.unlink(missing_ok=True)
        print(
            f"MERGE-STRINGS: OK merged {added} SideStore keys into main "
            f"bundle ({len(orig)} -> {len(check)})"
        )
        return 0
    except Exception as e:  # noqa: BLE001 - never fail the build
        print(f"MERGE-STRINGS: FAIL {e}; restoring original target file")
        try:
            if backup.is_file():
                shutil.copyfile(backup, DST)
                backup.unlink(missing_ok=True)
        except Exception as e2:  # noqa: BLE001
            print(f"MERGE-STRINGS: restore failed: {e2}")
        return 0


if __name__ == "__main__":
    sys.exit(main())
