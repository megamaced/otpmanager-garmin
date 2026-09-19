import Toybox.Application;
import Toybox.Lang;
import Toybox.StringUtil;

// What the app is configured with, gathered from three sources that each own a
// different part of it:
//
//   the settings screen   the Nextcloud URL, and the vault password
//   signing in            the login name and the app password
//   the seal              all three of those, once a PIN exists
//
// Only the first is typed on a phone. The login name and app password are never
// typed anywhere: Login Flow v2 returns them and they go straight to watch
// storage, which — unlike the properties behind the settings screen — does not
// sync anywhere.
class Config {

    var serverUrl as String;
    var username as String;
    var appPassword as String;
    var otpPassword as String;

    // The PIN-derived key, while the app is unlocked. Held so the account cache
    // can be encrypted under it — see CacheBox. Null on a build with no PIN,
    // where there is no key and nothing to encrypt with.
    private var _localKey as ByteArray?;

    function initialize() {
        serverUrl = trimTrailingSlash(read("serverUrl"));

        // Sealed, and so empty until the PIN opens the blob. The vault password
        // included: sealing cleared it from the settings screen, and the copy
        // inside the blob is the only one left.
        if (isSealed()) {
            username = "";
            appPassword = "";
            otpPassword = "";
            return;
        }

        username = CredentialStore.username();
        appPassword = CredentialStore.appPassword();
        otpPassword = read("otpPassword");
    }

    // An app password belongs to the server that issued it and to no other.
    // Pointing the app at a different host must not send it there — so a
    // credential whose bound origin no longer matches counts as no credential,
    // and the app asks for a fresh sign-in against the new server.
    function credentialsMatchServer() as Boolean {
        var bound = CredentialStore.boundServer();
        if (bound.equals("")) {
            // Baked into a sideload, where the build decided both halves.
            return true;
        }
        return sameOrigin(bound, serverUrl);
    }

    function isSealed() as Boolean {
        return !CredentialStore.sealedText().equals("");
    }

    // Null on a build with no PIN, where the credentials are held as they are.
    function sealedBlob() as SealedBlob? {
        var encoded = CredentialStore.sealedText();
        if (encoded.equals("")) {
            return null;
        }
        return Sealed.parse(encoded);
    }

    function localKey() as ByteArray? {
        return _localKey;
    }

    function setLocalKey(key as ByteArray) as Void {
        _localKey = key;
    }

    function unlock(credentials as Credentials) as Void {
        username = credentials.username;
        appPassword = credentials.appPassword;
        otpPassword = credentials.otpPassword;
    }

    function credentials() as Credentials {
        return new Credentials(username, appPassword, otpPassword);
    }

    // A vault password sitting in the settings screen while a seal already
    // holds one. It means the wearer is changing it — there is no other way to,
    // since the field is blanked the moment it is sealed — so the next unlock
    // re-seals under it and blanks the field again.
    function pendingOtpPassword() as String {
        return read("otpPassword");
    }

    function clearPendingOtpPassword() as Void {
        Application.Properties.setValue("otpPassword", "");
    }

    // Enough to know which server to sign in to, whether or not there is yet
    // anything to sign in with.
    function hasServer() as Boolean {
        return !serverUrl.equals("");
    }

    // A completed sign-in, held in the clear or opened from a seal.
    function hasCredentials() as Boolean {
        return !username.equals("") && !appPassword.equals("");
    }

    function isComplete() as Boolean {
        return hasServer() && hasCredentials() && !otpPassword.equals("");
    }

    // Connect IQ refuses plain HTTP outright, so this cannot leak a credential
    // — but it fails as an opaque error code partway through a request chain.
    // Catching it here turns that into something the wearer can act on.
    function isSecure() as Boolean {
        return isHttpsUrl(serverUrl);
    }

    // The part of a URL that decides who a credential is being sent to:
    // scheme and authority, lowercased, with everything from the first "/",
    // "?" or "#" dropped. Null when the URL is not an absolute HTTPS one.
    //
    // Paths are deliberately not compared. Nextcloud can be served from a
    // subdirectory and its own idea of its URL — whatever overwrite.cli.url
    // says — need not match what was typed character for character. The host
    // is what matters: it is who receives the app password.
    static function originOf(url as String) as String? {
        if (!isHttpsUrl(url)) {
            return null;
        }

        var rest = url.substring(8, url.length()) as String;
        var chars = rest.toCharArray();
        var end = chars.size();
        for (var i = 0; i < chars.size(); i++) {
            var c = chars[i];
            if (c == '/' || c == '?' || c == '#') {
                end = i;
                break;
            }
        }

        var authority = rest.substring(0, end) as String;
        return "https://" + authority.toLower();
    }

    static function sameOrigin(a as String, b as String) as Boolean {
        var left = originOf(a);
        var right = originOf(b);
        return left != null && right != null && left.equals(right);
    }

    // Absolute, HTTPS, and with an authority. URI schemes are case-insensitive,
    // and "https://" on its own is a prefix rather than a host.
    static function isHttpsUrl(url as String) as Boolean {
        if (url.length() <= 8) {
            return false;
        }

        var scheme = url.substring(0, 8);
        if (scheme == null || !scheme.toLower().equals("https://")) {
            return false;
        }

        // The authority runs to the first "/", "?" or "#", so if one of those
        // opens it there is no host at all.
        var rest = url.substring(8, url.length());
        if (rest == null) {
            return false;
        }
        var first = rest.toCharArray()[0];
        return first != '/' && first != '?' && first != '#';
    }

    function apiUrl(path as String) as String {
        return serverUrl + "/ocs/v2.php/apps/otpmanager" + path;
    }

    function authHeader() as String {
        var encoded = StringUtil.convertEncodedString(username + ":" + appPassword, {
            :fromRepresentation => StringUtil.REPRESENTATION_STRING_PLAIN_TEXT,
            :toRepresentation => StringUtil.REPRESENTATION_STRING_BASE64
        }) as String;
        return "Basic " + encoded;
    }

    // Changing any of these invalidates the cached account list.
    function fingerprint() as Number {
        return (serverUrl + "|" + username + "|" + otpPassword).hashCode();
    }

    private function read(key as String) as String {
        var value = Application.Properties.getValue(key);
        if (value instanceof String) {
            return value;
        }
        return "";
    }

    private function trimTrailingSlash(url as String) as String {
        var chars = url.toCharArray();
        var end = chars.size();
        while (end > 0 && chars[end - 1] == '/') {
            end--;
        }

        if (end == chars.size()) {
            return url;
        }

        var result = "";
        for (var i = 0; i < end; i++) {
            result += chars[i].toString();
        }
        return result;
    }
}
