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

You never type that app password. The watch asks Nextcloud for one of its own
with [Login Flow v2](https://docs.nextcloud.com/server/stable/developer_manual/client_apis/LoginFlow/index.html):
it opens the Nextcloud login page on your phone, you sign in there — SSO, 2FA
and all — and the watch polls until Nextcloud hands back a fresh app password,
revocable on its own under **Settings → Security → Devices & sessions**.

The account list is cached on the watch, so the app opens instantly and keeps
working with no phone nearby. Only the **Refresh** entry at the bottom of the
list goes back to the server — launching the app does not.

## Installing

There is no Connect IQ store build, so the app is sideloaded: you build it and
copy it to the watch.

Configuration is part of the build rather than a later step, because **Garmin
supports no settings UI for sideloaded apps** — a sideloaded app does not appear
in the Connect IQ mobile app at all, and Garmin Express does not offer its
settings either. There is nowhere to type the server details afterwards, so they
go in beforehand.

> If you would rather type the settings on your phone than rebuild for every
> change, upload it to your own account as a **beta app** instead — see
> [Or upload it as a beta](#or-upload-it-as-a-beta-instead) below. Steps 1 and 2
> here are needed either way.

### 1. Install the Connect IQ SDK

Get it through Garmin's [SDK Manager](https://developer.garmin.com/connect-iq/sdk/),
which needs a free Garmin account. Install the SDK and the device profile for
your watch (`venu3s`, `venu3` or `vivoactive5`).

> On a current Linux distro the SDK Manager will not start: it needs
> `webkit2gtk-4.0` and `libsoup2.4`, which have aged out of every shipping
> release. Running it in an Ubuntu 22.04 container works.

### 2. Generate a developer key

Every `.prg` has to be signed, even for sideloading. Any RSA key will do — it
just has to stay the same across rebuilds:

```bash
mkdir -p ~/.Garmin/keys && cd ~/.Garmin/keys
openssl genrsa -out developer_key.pem 4096
openssl pkcs8 -topk8 -inform PEM -outform DER -nocrypt \
    -in developer_key.pem -out developer_key.der
chmod 600 developer_key.*
```

### 3. Enter your server details

```bash
cp local.properties.example local.properties
$EDITOR local.properties          # gitignored; never commit it
```

| Setting | What it is |
|---|---|
| `serverUrl` | e.g. `https://cloud.example.com` — must be `https://` |
| `username` | your Nextcloud **user ID** (see below) |
| `appPassword` | Nextcloud → **Settings → Security → Devices & sessions** |
| `otpPassword` | your OTP Manager vault password |
| `pin` | optional, 4–8 digits — see [Locking the app](#locking-the-app-with-a-pin) |

This is the sideload route, where the whole configuration has to be compiled in.
A store or beta install types only two of these — the URL and the vault
password — and signs in for the rest.

Use a Nextcloud **app password**, not your login password — it can be revoked on
its own and it sidesteps two-factor prompts.

`username` is the Nextcloud user ID, which is not always the short name you type
at a login form. Servers that provision users through OIDC or SSO commonly set
it to the email address instead. The app-password screen shows the login name to
use, and `GET /ocs/v2.php/cloud/user` returns it as `id` if you want to be sure.

Leave `otpPassword` as any non-empty value if your vault has no encryption
password; it is ignored then.

### 4. Build

```bash
./build.sh local
```

`build.sh` reads the active SDK from `~/.Garmin/ConnectIQ/current-sdk.cfg` and
the key from `~/.Garmin/keys/developer_key.der` (override with `DEVELOPER_KEY`).
It writes `build/otpmanager-venu3s.prg` with your values compiled in as the
property defaults, then restores `resources/properties.xml` — including if the
build fails — so credentials are never left in the working tree.

> Without a `pin`, the resulting `.prg` contains both passwords in the clear.
> Treat that file the way you would treat the credentials themselves. With a
> `pin` set it carries ciphertext instead, and the plaintext never reaches the
> build at all.

Plain `./build.sh` builds every supported device with empty defaults. That is
the right thing for a store submission and useless on a sideloaded watch.

### 5. Copy it to the watch

Plug the watch in over USB. It enumerates as **MTP**, not as a USB mass storage
device, so there is no block device to mount — the file goes through the
desktop's MTP mount instead. On Linux that needs `gvfs-backends` and `libmtp`.

`cp` does not work here: writing into a gvfs MTP mount through ordinary POSIX
calls fails with `Operation not supported`. Use `gio`, which goes through the
GVfs API:

```bash
gio mount -l | grep mtp://          # find the device address
gio copy build/otpmanager-venu3s.prg \
    "mtp://<device>/Internal Storage/GARMIN/Apps/otpmanager-venu3s.prg"
```

The destination is `GARMIN/Apps/` on the watch's internal storage. Check the
capitalisation against the device rather than assuming — it is `Apps` on a
Venu 3S, though `APPS` is what most Connect IQ documentation says, and the
directory is not created for you if you get it wrong.

On macOS use [Android File Transfer](https://www.android.com/filetransfer/), and
on Windows the watch appears in Explorer; drag the `.prg` into the same folder.

Unplug the watch. The app appears in the **watch's** activity/app list as
**OTP Manager** — not in the Connect IQ mobile app, which only ever lists
store-installed apps.

> **The `.prg` disappears from `GARMIN/Apps` once installed, and that is the
> success signal.** The watch ingests it into internal storage on eject and
> deletes the file. What it leaves behind is a `.SET` of the same name in
> `GARMIN/Apps/SETTINGS`, holding the app's settings. An empty `GARMIN/Apps`
> next time you plug in means the install worked, not that it vanished.

### Changing the configuration later

Edit `local.properties`, run `./build.sh local` again, and copy the new `.prg`
across as in step 5 — there is no old one to overwrite, since the watch consumed
it at install time.

Also delete the matching `.SET` file from `GARMIN/Apps/SETTINGS`. It holds the
values captured at the previous install and overrides the new compiled-in
defaults, so without this the app appears to ignore its new configuration. The
watch recreates it on the next eject. This is only needed when the values
change; reinstalling the same configuration can leave it alone.

> Sideloading involves no Garmin account — that is only needed to download the
> SDK in the first place.

> If the app is ever published to the Connect IQ Store, none of this applies:
> store-installed apps get the normal settings screen in Garmin Connect, which is
> why the committed `properties.xml` ships with empty defaults.

### Or upload it as a beta instead

The Connect IQ Store has a **Beta App** slot whose whole purpose is this: it
lets you "test app settings and Garmin Connect integration in production without
releasing the app". A beta upload installs through the normal store path, so it
appears in **My Device Apps** and gets the real settings screen in Garmin
Connect and Garmin Express — no baking, no rebuild to change a value, and no
review.

```bash
./build.sh beta        # a .iq under the beta app id in build.sh
```

Upload `build/otpmanager-beta.iq` at
[developer.garmin.com](https://developer.garmin.com/connect-iq/submit-an-app/)
with the **Beta App** box ticked, then install it from the store as usual. The
beta uses a different app id from the production build so the store treats it as
a separate listing; the same developer key signs both, and you can re-upload it
as often as you like. `./build.sh export` produces the production `.iq` when
there is something to release.

Only your own Garmin account can see or install it — there is no way to invite
other testers from the developer dashboard.

### Setting it up on the watch

A store or beta install is configured in two places, and only the first of them
is a keyboard.

In Garmin Connect, under the app's settings:

| Setting | What it is |
|---|---|
| Nextcloud URL | e.g. `https://cloud.example.com` — must be `https://` |
| OTP Manager password | your vault password |

The vault password has to be typed because nothing can tell the watch what it
is: it is the key your secrets are encrypted under, and the server has never
seen it either.

Then, on the watch:

1. **Sign in** — the watch asks Nextcloud to start a login, and a notification
   appears on your phone. Tap it, sign in in the web view that opens, and grant
   access. The watch is polling while you do, and moves on by itself; it gives
   up after five minutes, and the row that started it will say so.
2. **Set a PIN**, or **Not now** — offered once, straight after signing in, and
   available afterwards under **Options**.

Nothing else is typed. The login name and the app password come back from
Nextcloud and go straight into the watch's own storage, which — unlike the
settings behind Garmin Connect — does not sync anywhere.

**Options** on the account list also has **Sign out**, which forgets the
credentials and the cached accounts and returns to the sign-in screen. It does
not revoke anything: the app password stays valid until you remove it in
Nextcloud, which is the thing to do if the watch itself is gone.

To change the vault password later, type the new one into the settings screen.
The next unlock re-seals under it and blanks the field again.

## Locking the app with a PIN

Set a 4 to 8 digit PIN and the app follows the same rule Garmin Pay uses for its
wallet passcode: **entering it once keeps the app open for 24 hours, and only
while the watch stays on your wrist.** Take the watch off and the PIN is needed
again.

Garmin exposes no hook into Garmin Pay itself — there is no wallet API, no NFC
access, and no way to raise the system passcode prompt. What it does expose is
the signal Garmin Pay's own rule turns on. The manual says the passcode comes
back if you "remove the watch from your wrist **or disable heart rate
monitoring**", and the heart rate history is readable by any app, with no
permission and no manifest change.

The app walks that history backwards from now to the moment you unlocked, and
asks one question: did a usable reading turn up at least every ten minutes the
whole way back? If not — a gap, a long outage, or history that does not reach
that far — it locks. Heart rate history does not survive a power cycle either,
so rebooting the watch always locks it.

A single invalid reading does **not** count as the watch coming off. The optical
sensor drops readings constantly on a wrist that never moved — on a Venu 3S,
about seven of every sixty samples — so treating one as evidence of removal
locks the app at random. Removal looks like a *run* of them, long enough that no
usable reading turns up for ten minutes.

Setting a PIN also encrypts both passwords rather than just hiding the screen
behind them. They are sealed into one AES-256-CBC blob keyed on the PIN, and
nothing else on the watch holds them.

The PIN is chosen on the watch, on the same keypad that afterwards asks for it —
straight after signing in, or later under **Options**. You type it twice, with
the ✓ key that appears on the keypad while a PIN is being chosen: the length is
fixed once it is set, so unlocking needs no confirm key, but choosing one does.
Only when both entries match is anything sealed.

It is never typed into Garmin Connect and there is no setting for it. Sealing
takes the app password out of the watch's storage and the vault password off the
settings screen in the same moment, so from then on the blob is the only copy of
either. On a sideload `tools/seal.py` does the same thing at build time, from
the `pin` in `local.properties`, and the plaintext never reaches the build.

**Be clear about what that buys.** Against someone who picks up your watch, it
is the real thing: they get a keypad and nothing else. Against someone who gets
hold of the `.prg` or the watch's storage, it raises the cost of a guess and no
more. Connect IQ has no PBKDF2 and nothing memory-hard, so the key is iterated
SHA-256 — 5000 rounds, which is about as much as a watch can do while you wait —
and a short numeric PIN does not survive an offline attack on any real hardware.
Keep treating the `.prg` as sensitive.

While the 24 hours are running, the key derived from your PIN is held in the
app's storage so the grace period can work at all. It is erased the moment the
unlock ends.

| | |
|---|---|
| Grace period | `PinLock.GRACE_SECONDS` |
| Longest run without a usable reading that still counts as worn | `PinLock.MAX_SAMPLE_GAP` |
| Rounds per guess | `Sealed.ITERATIONS`, and the same constant in `tools/seal.py` |

The iteration count is written into each sealed blob, so raising it later does
not strand a seal made under the old one. `./build.sh test` logs what a
derivation costs; the simulator runs on your workstation's CPU, so treat that
number as a floor and watch the ring on the actual watch.

## Limitations

- **TOTP only.** HOTP accounts appear in the list but say so when opened —
  generating one has to advance a server-side counter, which is not implemented.
- **No SHA-512.** Connect IQ offers SHA-1 and SHA-256 only. SHA-512 accounts
  appear in the list and say so when opened. SHA-1, the default, is fine.
- Accounts are listed **grouped by issuer**, then by name, case-insensitively.
  One with no issuer sorts under its own name. The server's own order is not
  useful on a watch, and there is no way to re-sort from the device.
- A provider or account name too long for the screen **scrolls** rather than
  being cut off. Garmin's touch devices never mark a list row as focused, so
  there is no "selected" row to scroll on demand — every over-long label
  scrolls, and the animation stops entirely when nothing on screen needs it.
- **Shared accounts are not shown**, only your own. `GET /accounts` returns
  both; entries flagged `isShared` are skipped, because a locked share is
  encrypted with the sharing password rather than your vault key.
- The watch clock drives the codes. Garmin keeps it synced; a watch that has
  been off-grid for a long time may drift far enough to matter.

## Security

Getting a code onto your wrist means the watch can compute it, so the watch
holds everything needed to do that.

**Without a PIN**, that is as direct as it sounds:

- The Nextcloud app password is held in the watch's own storage, in the clear.
  It never passes through Garmin Connect, but Connect IQ has no encrypted
  storage to put it in either.
- The vault password sits in Connect IQ application properties, in the clear,
  because that is where the settings screen you typed it into keeps it. Masked
  on entry, and synced to your phone like any other setting.
- The cached account list holds secrets exactly as the server sent them, still
  encrypted — but the key is derived from a password sitting next to it.

Treat the watch as you would an unlocked authenticator app. If you lose it,
revoke the Nextcloud app password in **Settings → Security → Devices &
sessions**; that cuts off refreshes, though a cached list will still generate
codes until the app is deleted. Signing out on the watch clears the credentials
and the cache but revokes nothing, so it is not a substitute.

**With a PIN**, neither password is stored anywhere in the clear, and a watch
that has been off your wrist shows a keypad rather than your codes. That defeats
someone who picks the watch up. It does not defeat someone who gets the `.prg`
or the watch's storage and attacks the PIN offline — see
[Locking the app](#locking-the-app-with-a-pin) for why a watch cannot make a
four to eight digit PIN expensive enough for that. Revoking the app password is
still the thing to do if you lose the watch.

The upstream scheme itself is worth knowing about: the IV is per user rather
than per secret, and there is no authentication tag, so a wrong password is
detected only by an implausible PKCS#7 padding. That is upstream's design, not
this app's, and this app is deliberately bug-compatible with it.

## Development

```bash
./build.sh              # one signed .prg per device, into build/
./build.sh local        # one .prg with local.properties compiled in
./build.sh test         # unit tests, in the simulator
./build.sh export       # a .iq for the store
./build.sh beta         # a .iq for the store's Beta App slot
```

The tests cover base32 decoding, the RFC 6238 vectors for SHA-1 and SHA-256,
AES decryption against a ciphertext produced the way the server produces one,
the sealed blob format, what a sign-in response has to contain, and the lock
rule. They run on the device VM, not on a host reimplementation.

Two of them are worth knowing about. One opens a sealed blob produced by
`tools/seal.py`, so the watch and the build-time sealer are checked against each
other rather than each against itself — the key derivation has to agree
byte for byte or that test fails. The other feeds the wear rule fabricated
heart rate samples, which is the only way to take a watch off a wrist from a
test suite.

The simulator has the same `webkit2gtk-4.0` problem as the SDK Manager, and in
a container it also needs `libusb-1.0-0`. Run it with host networking:
`monkeydo` is Java, has no counterpart inside the image, and reaches the
simulator on `localhost:1234`.

## Licence

MIT — see [LICENSE](LICENSE). Not affiliated with the upstream OTP Manager
project or with Garmin.
