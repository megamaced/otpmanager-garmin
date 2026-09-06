# OTP Manager for Garmin

A Connect IQ watch app that reads your
[Nextcloud OTP Manager](https://github.com/matteo-convertino/otpmanager-nextcloud)
vault and generates TOTP codes on the watch. Open it, pick an account, read the
code off your wrist.

| Accounts | Code |
|---|---|
| ![Account list](docs/screenshot-list.png) | ![Code](docs/screenshot-code.png) |

Supported devices: **Venu 3S**, **Venu 3**, **vívoactive 5**.

## How it works

The app talks to the OTP Manager OCS API over HTTPS, authenticating as you with
a Nextcloud app password:

1. `GET /password/status` — does the vault use an encryption password?
2. `POST /password/check` — if it does, this returns your per-user IV.
3. `GET /accounts` — the account list, secrets still encrypted.

Secrets are decrypted on the watch, exactly as the web client does it:
AES-256-CBC, keyed on `SHA-256(your OTP Manager password)`, with the IV from
step 2. Codes are then generated per RFC 6238.

The account list is cached on the watch, so the app opens instantly and keeps
working with no phone nearby. Only the **Refresh** entry at the bottom of the
list goes back to the server — launching the app does not.

## Setup

### 1. Create a Nextcloud app password

In Nextcloud, go to **Settings → Security → Devices & sessions** and create an
app password. Use that, not your login password — it can be revoked on its own
and it sidesteps two-factor prompts.

### 2. Fill in the app settings

In Garmin Connect Mobile: **⋯ → Connect IQ Store → My Device → Apps → OTP
Manager → Settings**. In Garmin Express: select the device, then **Apps**.

| Setting | Example |
|---|---|
| Nextcloud URL | `https://cloud.example.com` |
| Nextcloud user | `alice` |
| Nextcloud app password | the app password from step 1 |
| OTP Manager password | your OTP Manager vault password |

Leave **OTP Manager password** as any non-empty value if your vault has no
encryption password set; it is ignored in that case.

Changing the URL, user or vault password clears the cached accounts.

## Limitations

- **TOTP only.** HOTP accounts appear in the list but say so when opened —
  generating one has to advance a server-side counter, which is not implemented.
- **No SHA-512.** Connect IQ offers SHA-1 and SHA-256 only. SHA-512 accounts
  appear in the list and say so when opened. SHA-1, the default, is fine.
- **Shared accounts are not shown**, only your own.
- The watch clock drives the codes. Garmin keeps it synced; a watch that has
  been off-grid for a long time may drift far enough to matter.

## Security

Getting a code onto your wrist means the watch can compute it, so the watch
holds everything needed to do that:

- The Nextcloud app password and the vault password are stored in Connect IQ
  application properties, in the clear.
- The cached account list holds secrets exactly as the server sent them, still
  encrypted — but the key is derived from a password sitting next to it.

Treat the watch as you would an unlocked authenticator app. If you lose it,
revoke the Nextcloud app password; that cuts off refreshes, though a cached
list will still generate codes until the app is deleted.

The upstream scheme itself is worth knowing about: the IV is per user rather
than per secret, and there is no authentication tag, so a wrong password is
detected only by an implausible PKCS#7 padding. That is upstream's design, not
this app's, and this app is deliberately bug-compatible with it.

## Building

Needs the Connect IQ SDK and a developer key. `build.sh` reads the active SDK
from `~/.Garmin/ConnectIQ/current-sdk.cfg` and the key from
`~/.Garmin/keys/developer_key.der` (override with `DEVELOPER_KEY`):

```bash
./build.sh              # one signed .prg per device, into build/
./build.sh test         # unit tests, in the simulator
```

The tests cover base32 decoding, the RFC 6238 vectors for SHA-1 and SHA-256,
and AES decryption against a ciphertext produced the way the server produces
one. They run on the device VM, not on a host reimplementation.

On a current Linux distro the SDK's simulator will not start: it needs
`webkit2gtk-4.0` and `libsoup2.4`, which have aged out of every shipping
release. Running it in an Ubuntu 22.04 container works — that container also
needs `libusb-1.0-0`.

### Sideloading

The watch enumerates as MTP, so copy the `.prg` across rather than mounting it:

```bash
cp build/otpmanager-venu3s.prg \
   "$(ls -d /run/user/$UID/gvfs/mtp*/Internal\ Storage)/GARMIN/APPS/"
```

The app appears after unplugging.

## Licence

MIT — see [LICENSE](LICENSE). Not affiliated with the upstream OTP Manager
project or with Garmin.
