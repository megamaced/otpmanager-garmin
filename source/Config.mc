import Toybox.Application;
import Toybox.Lang;
import Toybox.StringUtil;

// The values the user fills in from Garmin Connect / Garmin Express. The two
// passwords are empty until the PIN opens them, on a build that has one.
class Config {

    var serverUrl as String;
    var username as String;
    var appPassword as String;
    var otpPassword as String;

    function initialize() {
        serverUrl = trimTrailingSlash(read("serverUrl"));
        username = read("username");
        appPassword = read("appPassword");
        otpPassword = read("otpPassword");

        // A sealed build must never fall back on plaintext left behind by an
        // install that predates the PIN: a stale .SET would quietly unlock it.
        if (!read("sealed").equals("") && read("pin").equals("")) {
            appPassword = "";
            otpPassword = "";
        }
    }

    // Null on a build with no PIN, where the credentials are in the properties
    // in the clear — which is how this app worked before the PIN existed, and
    // still the default for a build that does not ask for one.
    function sealedBlob() as SealedBlob? {
        var encoded = read("sealed");
        if (encoded.equals("")) {
            return null;
        }
        return Sealed.parse(encoded);
    }

    function unlock(credentials as Credentials) as Void {
        appPassword = credentials.appPassword;
        otpPassword = credentials.otpPassword;
    }

    // A PIN typed into Garmin Connect and not yet acted on. Garmin Connect is
    // the only place a store or beta build can be given one, and it keeps
    // whatever it is given in the clear, so this is a state to get out of
    // rather than one to stay in. Empty on a sideload, which seals at build
    // time and never has a plaintext stage at all.
    function pendingPin() as String {
        return read("pin");
    }

    function canSeal() as Boolean {
        return Sealed.isPin(pendingPin())
            && !appPassword.equals("")
            && !otpPassword.equals("");
    }

    // Stores the seal and clears every plaintext it replaces, including the PIN
    // itself. Deliberately not done at launch: the wearer retypes the PIN on
    // the watch first, so a typo in Garmin Connect cannot take the only copy of
    // the credentials with it.
    function completeSeal(blob as String) as Void {
        Application.Properties.setValue("sealed", blob);
        Application.Properties.setValue("pin", "");
        Application.Properties.setValue("appPassword", "");
        Application.Properties.setValue("otpPassword", "");

        // Any earlier unlock belongs to credentials that are no longer current.
        PinLock.forget();
    }

    // Enough to know which server to talk to, whether or not the credentials
    // for it have been unsealed yet.
    function hasServer() as Boolean {
        return !serverUrl.equals("") && !username.equals("");
    }

    function isComplete() as Boolean {
        return !serverUrl.equals("")
            && !username.equals("")
            && !appPassword.equals("")
            && !otpPassword.equals("");
    }

    // Connect IQ refuses plain HTTP outright, so this cannot leak a credential
    // — but it fails as an opaque error code partway through a request chain.
    // Catching it here turns that into something the wearer can act on.
    function isSecure() as Boolean {
        return isHttpsUrl(serverUrl);
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
