import Toybox.Application;
import Toybox.Lang;
import Toybox.StringUtil;

// The four values the user fills in from Garmin Connect / Garmin Express.
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
