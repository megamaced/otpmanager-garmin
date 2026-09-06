#!/usr/bin/env python3
"""Bake local.properties into resources/properties.xml as defaults.

Garmin supports no settings UI for sideloaded apps, so a personal build has to
carry its configuration inside the .prg. build.sh restores properties.xml
afterwards; nothing here is ever committed.
"""
import pathlib
import re
import sys

PROPERTIES = pathlib.Path("resources/properties.xml")


def main() -> int:
    local = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "local.properties")
    if not local.exists():
        print(f"{local} not found (see local.properties.example)", file=sys.stderr)
        return 1

    text = PROPERTIES.read_text()
    baked = []

    for line in local.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue

        key, value = line.split("=", 1)
        key, value = key.strip(), value.strip()

        pattern = r'(<property id="%s" type="string">)[^<]*(</property>)' % re.escape(key)
        text, count = re.subn(pattern, lambda m: m.group(1) + value + m.group(2), text)
        if count == 0:
            print(f"no property named {key!r} in {PROPERTIES}", file=sys.stderr)
            return 1
        baked.append(key)

    PROPERTIES.write_text(text)
    # Deliberately prints only the names — the values are credentials.
    print("baked: " + ", ".join(baked))
    return 0


if __name__ == "__main__":
    sys.exit(main())
