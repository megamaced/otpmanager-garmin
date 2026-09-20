# Privacy

NC OTP Manager is a client for a Nextcloud server that you run and control. It
has no backend of its own.

**Nothing is sent to the developer, and nothing is sent to any third party.**
There is no analytics, no telemetry, no crash reporting and no advertising.

## What the app sends, and where

Every network request goes to the Nextcloud server whose address you enter in
the app's settings, and to no other host. The app refuses any address that is
not HTTPS.

| Sent | To | When |
|---|---|---|
| Your Nextcloud login name and app password | your server | with every request, as HTTP Basic authentication |
| Your OTP Manager vault password | your server | on each refresh, to `/password/check`, so the server can verify it against the hash it stores and return the decryption IV |
| A login token | your server | while signing in |

Your account secrets are decrypted on the watch. The key is derived from your
vault password and is never transmitted.

Signing in opens your server's own login page on your phone, through the Garmin
Connect app. The watch is issued its own Nextcloud app password and never asks
you to type your account password.

## What the app stores on the watch

- Your Nextcloud login name and app password.
- Your vault password.
- The account list from your last successful refresh, so the app opens without
  your phone in range.

If you set a PIN, the two passwords are encrypted under it, and so is the
cached account list when your vault has no password of its own. Connect IQ
provides no encrypted storage of its own, so without a PIN these are held as
they are — as they are in any Connect IQ app that needs a credential.

**Sign out** clears all of it, and so does deleting the app. Signing out does
not revoke the app password at the server: do that in Nextcloud under Settings,
Security, Devices & sessions.

## What passes through Garmin

Two values are entered on the app's settings screen rather than on the watch:
your server address and your vault password. Connect IQ settings are delivered
to the watch through Garmin's infrastructure, so those two pass through it, and
Garmin's own privacy policy governs that leg. This is a property of the
platform's settings mechanism and not something the app can opt out of.

Your login name and app password are **not** among them. They are returned by
your own server during sign-in and written straight to watch-local storage,
which does not sync anywhere.

## Contact

Questions, or a privacy problem to report: open an issue at
<https://github.com/megamaced/otpmanager-garmin/issues>.
