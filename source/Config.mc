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
