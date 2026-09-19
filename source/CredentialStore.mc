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
    const SERVER = "boundServer";
    const USERNAME = "username";
    const APP_PASSWORD = "appPassword";

    // Compiled in by tools/bake-properties.py and by nothing else: it has no
    // settings entry, so there is nothing that can type one, and a build that
    // baked no credentials carries an empty one.
    const BUILD_SOURCE = "buildSource";
    const BAKED = "local";

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

    // The origin that issued the stored app password. Empty for a sideload,
    // where nothing was signed in for and the build chose both halves itself.
    function boundServer() as String {
        return stringAt(SERVER);
    }

    // Credentials this app wrote before it recorded which server had issued
    // them. There is no way to find out now, and binding them to whatever the
    // settings screen currently says would assume the answer to the one
    // question the binding exists to ask.
    function hasUnboundCredentials() as Boolean {
        return isUnbound(hasStoredCredentials() || hasPropertyCredentials(),
            boundServer(), isBakedBuild());
    }

    // The decision by itself, so it can be tested without a store behind it.
    //
    // Credentials the build compiled in were never issued by anybody: there is
    // no server to have recorded and there never was one. That stays true after
    // a PIN is set on the watch, because sealing rewrites the credentials
    // without changing where they came from. Everything else that names no
    // server is a credential this version cannot account for.
    //
    // Which of the two it is has to be asked of the **build**, not of where the
    // credentials are sitting. Until signing in existed the settings screen
    // wrote the login name and the app password into the very properties a
    // sideload bakes them into, so an upgraded store install looks exactly like
    // a sideload from the storage out.
    function isUnbound(present as Boolean, server as String, fromBuild as Boolean) as Boolean {
        return present && server.equals("") && !fromBuild;
    }

    // Whether this build carries credentials of its own.
    function isBakedBuild() as Boolean {
        return baked(BUILD_SOURCE).equals(BAKED);
    }

    // What the app put in storage: a seal, or a signed-in app password.
    function hasStoredCredentials() as Boolean {
        return !stringAt(SEALED).equals("")
            || !stringAt(USERNAME).equals("")
            || !stringAt(APP_PASSWORD).equals("");
    }

    // What is in the property store, wherever it came from — compiled into a
    // sideload, or typed into Garmin Connect by a version that predates the
    // login flow.
    function hasPropertyCredentials() as Boolean {
        return !baked("sealed").equals("")
            || !baked("username").equals("")
            || !baked("appPassword").equals("");
    }

    // What a sign-in produces. In the clear, because until a PIN exists there
    // is nothing to encrypt under — but on the watch only, and the vault
    // password is not here: that one is typed into the settings screen and
    // stays there until a seal replaces it.
    function storeSignIn(server as String, username as String, appPassword as String) as Void {
        Application.Storage.setValue(SERVER, server);
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
    // copy of either password is inside the blob. The bound server is left
    // exactly as it was — it is not a secret, a seal made from signed-in
    // credentials has to keep belonging to the host that issued them, and one
    // made from compiled-in credentials has no host to belong to.
    function storeSeal(blob as String) as Void {
        Application.Storage.setValue(SEALED, blob);
        Application.Storage.deleteValue(USERNAME);
        Application.Storage.deleteValue(APP_PASSWORD);
    }

    // Signing out. A sideload falls back to whatever was baked in, which is the
    // honest answer there — a credential compiled into the .prg cannot be
    // signed out of, only rebuilt away.
    // The copies an older version left in the property store. Blanked rather
    // than left alone, because Config reads them as a fallback and would go on
    // using them against whatever server the settings screen now names. A build
    // that compiled its own in never reaches this.
    function clearProperties() as Void {
        Application.Properties.setValue("sealed", "");
        Application.Properties.setValue("username", "");
        Application.Properties.setValue("appPassword", "");
    }

    function clear() as Void {
        Application.Storage.deleteValue(SEALED);
        Application.Storage.deleteValue(USERNAME);
        Application.Storage.deleteValue(APP_PASSWORD);
        Application.Storage.deleteValue(SERVER);
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
