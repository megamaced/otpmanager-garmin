import Toybox.Application;
import Toybox.Lang;

// Where the credentials live between launches, and the one rule that decides
// it: Application.Storage is what the app itself writes, and the application
// properties are only ever a seed baked into a sideload by
// tools/bake-properties.py, which has no settings screen to be filled from.
//
// The distinction is not tidiness. Properties are synced through Garmin's
// infrastructure to the phone; Storage never leaves the watch. Credentials
// obtained by signing in therefore go to Storage and stay there, and the only
// thing ever written back to a property is a blank — when sealing clears the
// vault password the wearer typed into the settings screen.
//
// Storage always wins over a baked property. A sideload can carry a seal made
// at build time, and a PIN set on the watch has to be able to replace it.
module CredentialStore {

    const SEALED = "sealedCredentials";
    const USERNAME = "username";
    const APP_PASSWORD = "appPassword";

    // The sealed blob, from wherever it came. Empty when there is none, which
    // is the state a build with no PIN stays in.
    function sealedText() as String {
        var stored = stringAt(SEALED);
        return stored.equals("") ? baked("sealed") : stored;
    }

    // Who the app password belongs to. Nextcloud calls it the login name, and
    // it is whatever the sign-in returned rather than anything typed.
    function username() as String {
        var stored = stringAt(USERNAME);
        return stored.equals("") ? baked("username") : stored;
    }

    function appPassword() as String {
        var stored = stringAt(APP_PASSWORD);
        return stored.equals("") ? baked("appPassword") : stored;
    }

    // What a sign-in produces. In the clear, because until a PIN exists there
    // is nothing to encrypt under — but on the watch only, and the vault
    // password is not here: that one is typed into the settings screen and
    // stays there until a seal replaces it.
    function storeSignIn(username as String, appPassword as String) as Void {
        Application.Storage.setValue(USERNAME, username);
        Application.Storage.setValue(APP_PASSWORD, appPassword);
        Application.Storage.deleteValue(SEALED);

        // A baked seal cannot be deleted, only written over. The only way to
        // reach a sign-in with one present is that it did not parse — a blob
        // from a version of the app that predates this — and leaving it would
        // keep the app looking sealed for ever after.
        Application.Properties.setValue("sealed", "");
    }

    // Replaces the plaintext rather than sitting beside it: after this the only
    // copy of either password is inside the blob.
    function storeSeal(blob as String) as Void {
        Application.Storage.setValue(SEALED, blob);
        Application.Storage.deleteValue(USERNAME);
        Application.Storage.deleteValue(APP_PASSWORD);
    }

    // Signing out. A sideload falls back to whatever was baked in, which is the
    // honest answer there — a credential compiled into the .prg cannot be
    // signed out of, only rebuilt away.
    function clear() as Void {
        Application.Storage.deleteValue(SEALED);
        Application.Storage.deleteValue(USERNAME);
        Application.Storage.deleteValue(APP_PASSWORD);
    }

    function stringAt(key as String) as String {
        var value = Application.Storage.getValue(key);
        return value instanceof String ? value : "";
    }

    function baked(key as String) as String {
        var value = Application.Properties.getValue(key);
        return value instanceof String ? value : "";
    }
}
