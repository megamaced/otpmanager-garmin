#!/usr/bin/env python3
"""Bake local.properties into a properties.xml written somewhere else.

Garmin supports no settings UI for sideloaded apps, so a personal build has to
carry its configuration inside the .prg. The values are credentials, so they are
never written into the tracked resources/properties.xml: --out names a copy that
build.sh keeps under build/ and deletes on exit. Nothing in the working tree is
modified, so an interrupted build cannot leave a password in a file git tracks.

Setting `pin` seals every credential under it at this point, so the .prg carries
ciphertext rather than passwords. Without a `pin` they are baked in as they are.
"""
import argparse
import pathlib
import re
import sys
from xml.sax.saxutils import escape

import seal

SOURCE = pathlib.Path("resources/properties.xml")
SEALED = ("username", "appPassword", "otpPassword")

# Set when this build carries credentials of its own. The app needs to tell
# those from credentials an earlier version left in the property store, which
# look identical once they are there: before signing in existed, the settings
# screen wrote the login name and the app password to these same properties.
CREDENTIALS = ("username", "appPassword", "sealed")
BUILD_SOURCE = "buildSource"
BAKED = "local"


def read(path: pathlib.Path) -> dict[str, str]:
    """key=value, one per line.

    The key is stripped and the value is not. A password may legitimately begin
    or end with a space, and silently trimming it builds an app that cannot log
    in for reasons nothing on the watch can explain. Whitespace that looks
    accidental is reported rather than removed.
    """
    values = {}
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if not line.strip() or line.lstrip().startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        if value != value.strip():
            print(f"{path}:{number}: warning: {key} has leading or trailing "
                  f"whitespace, which is kept", file=sys.stderr)
        values[key] = value
    return values


def bake(text: str, values: dict[str, str]) -> str:
    """Substitute into element content, escaped.

    An unescaped ampersand or less-than in a password produces XML that is not
    well formed and a build that fails several steps later; worse, raw text
    could close the element and change the structure of the resource.
    """
    for key, value in values.items():
        pattern = r'(<property id="%s" type="string">)[^<]*(</property>)' % re.escape(key)
        text, count = re.subn(pattern, lambda m: m.group(1) + escape(value) + m.group(2), text)
        if count == 0:
            raise KeyError(f"no property named {key!r} in {SOURCE}")
    return text


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", required=True, type=pathlib.Path,
                        help="where to write the baked properties.xml")
    parser.add_argument("local", nargs="?", default="local.properties", type=pathlib.Path)
    args = parser.parse_args()

    if not args.local.exists():
        print(f"{args.local} not found (see local.properties.example)", file=sys.stderr)
        return 1

    values = read(args.local)

    # The PIN itself is not a property: nothing on the watch reads one, and a
    # build that seals has no reason to carry the key to its own blob.
    pin = values.pop("pin", "")

    if pin:
        if not all(values.get(key) for key in SEALED):
            print("pin needs " + ", ".join(SEALED) + " to seal", file=sys.stderr)
            return 1
        try:
            values["sealed"] = seal.seal(values["username"], values["appPassword"],
                                         values["otpPassword"], pin)
        except ValueError as error:
            print(error, file=sys.stderr)
            return 1

        # The point of the exercise: the plaintext never reaches the build.
        for key in SEALED:
            values[key] = ""

    if any(values.get(key) for key in CREDENTIALS):
        values[BUILD_SOURCE] = BAKED

    try:
        baked = bake(SOURCE.read_text(encoding="utf-8"), values)
    except KeyError as error:
        print(error, file=sys.stderr)
        return 1

    args.out.write_text(baked, encoding="utf-8")
    # Deliberately prints only the names — the values are credentials.
    print("baked: " + ", ".join(sorted(key for key, value in values.items() if value)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
