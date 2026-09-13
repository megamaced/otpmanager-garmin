#!/usr/bin/env python3
"""Bake local.properties into resources/properties.xml as defaults.

Garmin supports no settings UI for sideloaded apps, so a personal build has to
carry its configuration inside the .prg. build.sh restores properties.xml
afterwards; nothing here is ever committed.

Setting `pin` seals both passwords under it at this point, so the .prg carries
ciphertext rather than credentials. Without a `pin` the passwords are baked in
as they are, which is how this worked before the PIN existed.
"""
import pathlib
import re
import sys

import seal

PROPERTIES = pathlib.Path("resources/properties.xml")
SEALED = ("appPassword", "otpPassword", "pin")


def read(path: pathlib.Path) -> dict[str, str]:
    values = {}
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key.strip()] = value.strip()
    return values


def main() -> int:
    local = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "local.properties")
    if not local.exists():
        print(f"{local} not found (see local.properties.example)", file=sys.stderr)
        return 1

    values = read(local)
    pin = values.get("pin", "")

    if pin:
        if not all(values.get(key) for key in ("appPassword", "otpPassword")):
            print("pin needs both appPassword and otpPassword to seal", file=sys.stderr)
            return 1
        try:
            values["sealed"] = seal.seal(values["appPassword"], values["otpPassword"], pin)
        except ValueError as error:
            print(error, file=sys.stderr)
            return 1

        # The point of the exercise: the plaintext never reaches the build.
        for key in SEALED:
            values[key] = ""

    text = PROPERTIES.read_text()
    for key, value in values.items():
        pattern = r'(<property id="%s" type="string">)[^<]*(</property>)' % re.escape(key)
        text, count = re.subn(pattern, lambda m: m.group(1) + value + m.group(2), text)
        if count == 0:
            print(f"no property named {key!r} in {PROPERTIES}", file=sys.stderr)
            return 1

    PROPERTIES.write_text(text)
    # Deliberately prints only the names — the values are credentials.
    print("baked: " + ", ".join(sorted(key for key, value in values.items() if value)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
