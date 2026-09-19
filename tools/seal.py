#!/usr/bin/env python3
"""Seal every credential under a PIN, in the format source/Sealed.mc reads.

    version:1  pinLength:1  iterations:4 (big endian)  salt:16  iv:16  ct:16n

and inside the ciphertext, PKCS#7 padded to the block size:

    b"OTPM"  length:1 username  length:1 appPassword  length:1 otpPassword

The key is iterated SHA-256 because that is all Connect IQ offers: there is no
PBKDF2 in the API and nothing memory-hard. Any change here has to be made in
Sealed.mc as well — Tests.mc opens a blob produced by this file, which is what
keeps the two honest.

Run directly to print a blob, which is how the test vector was produced:

    ./tools/seal.py --pin 1234 --username alice --app-password a \\
        --otp-password hunter2 --iterations 1000 --salt 000102...0f --iv 0f0e...00
"""
import argparse
import base64
import hashlib
import os
import struct
import sys

from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes

VERSION = 2
ITERATIONS = 5000
BLOCK = 16
SALT_SIZE = 16
IV_SIZE = 16
MAGIC = b"OTPM"
MIN_PIN = 4
MAX_PIN = 8


def derive(pin: str, salt: bytes, iterations: int) -> bytes:
    state = hashlib.sha256(salt + pin.encode("utf-8")).digest()
    for _ in range(iterations - 1):
        state = hashlib.sha256(state + salt).digest()
    return state


def is_pin(pin: str) -> bool:
    return MIN_PIN <= len(pin) <= MAX_PIN and pin.isdigit() and pin.isascii()


def seal(username: str, app_password: str, otp_password: str, pin: str,
         iterations: int = ITERATIONS,
         salt: bytes | None = None, iv: bytes | None = None) -> str:
    if not is_pin(pin):
        raise ValueError(f"the PIN must be {MIN_PIN} to {MAX_PIN} digits")

    user = username.encode("utf-8")
    app = app_password.encode("utf-8")
    otp = otp_password.encode("utf-8")
    if max(len(user), len(app), len(otp)) > 255:
        raise ValueError("a field longer than 255 bytes cannot be sealed")

    salt = salt if salt is not None else os.urandom(SALT_SIZE)
    iv = iv if iv is not None else os.urandom(IV_SIZE)

    body = (MAGIC + bytes([len(user)]) + user + bytes([len(app)]) + app
            + bytes([len(otp)]) + otp)
    padding = BLOCK - (len(body) % BLOCK)
    body += bytes([padding]) * padding

    encryptor = Cipher(algorithms.AES(derive(pin, salt, iterations)), modes.CBC(iv)).encryptor()
    blob = (bytes([VERSION, len(pin)]) + struct.pack(">I", iterations) + salt + iv
            + encryptor.update(body) + encryptor.finalize())

    return base64.b64encode(blob).decode("ascii")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pin", required=True)
    parser.add_argument("--username", required=True)
    parser.add_argument("--app-password", required=True)
    parser.add_argument("--otp-password", required=True)
    parser.add_argument("--iterations", type=int, default=ITERATIONS)
    parser.add_argument("--salt", help="hex, for a reproducible blob")
    parser.add_argument("--iv", help="hex, for a reproducible blob")
    args = parser.parse_args()

    print(seal(args.username, args.app_password, args.otp_password, args.pin, args.iterations,
               bytes.fromhex(args.salt) if args.salt else None,
               bytes.fromhex(args.iv) if args.iv else None))
    return 0


if __name__ == "__main__":
    sys.exit(main())
