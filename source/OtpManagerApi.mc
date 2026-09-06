import Toybox.Communications;
import Toybox.Lang;

// Talks to the Nextcloud OTP Manager OCS API. A refresh is three chained
// requests: does the vault have a password, what is its IV, and the accounts.
class OtpManagerApi {

    // Reported to the caller alongside a human-readable message.
    enum Result {
        RESULT_OK,
        RESULT_NOT_CONFIGURED,
        RESULT_AUTH_FAILED,
        RESULT_BAD_OTP_PASSWORD,
        RESULT_NETWORK_ERROR
    }

    private var _config as Config;
    private var _callback as (Method(result as Result, payload as Dictionary?, message as String?) as Void)?;
    private var _hasPassword as Boolean = false;
    private var _iv as String = "";

    function initialize(config as Config) {
        _config = config;
    }

    function refresh(callback as Method(result as Result, payload as Dictionary?, message as String?) as Void) as Void {
        _callback = callback;

        if (!_config.isComplete()) {
            report(RESULT_NOT_CONFIGURED, null, null);
            return;
        }

        Communications.makeWebRequest(
            _config.apiUrl("/password/status"),
            { "format" => "json" },
            getOptions(Communications.HTTP_REQUEST_METHOD_GET),
            method(:onPasswordStatus)
        );
    }

    function onPasswordStatus(responseCode as Number, data as Dictionary or String or Null) as Void {
        var payload = unwrap(responseCode, data);
        if (payload == null) {
            return;
        }

        _hasPassword = payload["hasPassword"] instanceof Boolean
            ? payload["hasPassword"] as Boolean
            : false;

        if (!_hasPassword) {
            // Without a vault password the server stores secrets in the clear.
            fetchAccounts();
            return;
        }

        Communications.makeWebRequest(
            _config.apiUrl("/password/check"),
            { "password" => _config.otpPassword },
            getOptions(Communications.HTTP_REQUEST_METHOD_POST),
            method(:onPasswordCheck)
        );
    }

    function onPasswordCheck(responseCode as Number, data as Dictionary or String or Null) as Void {
        if (responseCode == 400 || responseCode == 403) {
            report(RESULT_BAD_OTP_PASSWORD, null, null);
            return;
        }

        var payload = unwrap(responseCode, data);
        if (payload == null) {
            return;
        }

        if (!payload.hasKey("iv") || !(payload["iv"] instanceof String)) {
            report(RESULT_BAD_OTP_PASSWORD, null, null);
            return;
        }

        _iv = payload["iv"] as String;
        fetchAccounts();
    }

    function onAccounts(responseCode as Number, data as Dictionary or String or Null) as Void {
        var payload = unwrap(responseCode, data);
        if (payload == null) {
            return;
        }

        var raw = payload["data"];
        if (!(raw instanceof Array)) {
            report(RESULT_NETWORK_ERROR, null, "Unexpected response");
            return;
        }

        report(RESULT_OK, {
            "iv" => _iv,
            "encrypted" => _hasPassword,
            "accounts" => toAccounts(raw as Array)
        }, null);
    }

    private function fetchAccounts() as Void {
        Communications.makeWebRequest(
            _config.apiUrl("/accounts"),
            { "format" => "json" },
            getOptions(Communications.HTTP_REQUEST_METHOD_GET),
            method(:onAccounts)
        );
    }

    // Keeps only the fields the watch needs, so the cache stays small.
    private function toAccounts(raw as Array) as Array<Dictionary> {
        var accounts = [] as Array<Dictionary>;

        for (var i = 0; i < raw.size(); i++) {
            var item = raw[i];
            if (!(item instanceof Dictionary) || !(item["secret"] instanceof String)) {
                continue;
            }
            if (item["deletedAt"] != null) {
                continue;
            }

            accounts.add({
                "name" => asString(item, "name", "?"),
                "issuer" => asString(item, "issuer", ""),
                "secret" => item["secret"],
                "type" => asString(item, "type", "totp").toLower(),
                "period" => asNumber(item, "period", 30),
                "algorithm" => asString(item, "algorithm", "SHA1"),
                "digits" => asNumber(item, "digits", 6)
            });
        }

        return accounts;
    }

    // Unwraps the OCS envelope. Returns null after reporting the failure, so
    // callers can simply bail out.
    private function unwrap(responseCode as Number, data as Dictionary or String or Null) as Dictionary? {
        if (responseCode == 401) {
            report(RESULT_AUTH_FAILED, null, null);
            return null;
        }

        if (responseCode != 200 || !(data instanceof Dictionary)) {
            report(RESULT_NETWORK_ERROR, null, describe(responseCode));
            return null;
        }

        var ocs = data["ocs"];
        if (!(ocs instanceof Dictionary)) {
            report(RESULT_NETWORK_ERROR, null, "Not an OCS response");
            return null;
        }

        var meta = ocs["meta"];
        if (meta instanceof Dictionary && !isOk(meta)) {
            report(RESULT_NETWORK_ERROR, null, asString(meta, "message", "Server error"));
            return null;
        }

        var body = ocs["data"];
        // /accounts returns a bare list; wrap it so callers always see a Dictionary.
        return body instanceof Dictionary ? body : { "data" => body };
    }

    private function isOk(meta as Dictionary) as Boolean {
        var status = meta["status"];
        if (status instanceof String) {
            return status.equals("ok");
        }
        return false;
    }

    private function report(result as Result, payload as Dictionary?, message as String?) as Void {
        if (_callback != null) {
            _callback.invoke(result, payload, message);
        }
    }

    private function getOptions(httpMethod as Communications.HttpRequestMethod) as
        { :method as Communications.HttpRequestMethod,
          :headers as Dictionary,
          :responseType as Communications.HttpResponseContentType } {
        return {
            :method => httpMethod,
            :headers => {
                "Authorization" => _config.authHeader(),
                "OCS-APIRequest" => "true",
                "Accept" => "application/json",
                "Content-Type" => Communications.REQUEST_CONTENT_TYPE_JSON
            },
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };
    }

    private function describe(responseCode as Number) as String {
        if (responseCode == Communications.BLE_CONNECTION_UNAVAILABLE
            || responseCode == Communications.BLE_HOST_TIMEOUT) {
            return "No phone connection";
        }
        return "Error " + responseCode.toString();
    }

    // The lookup happens here rather than at the call site: Connect IQ types
    // Dictionary access as Any, which strict mode will not pass as a parameter.
    private function asString(source as Dictionary, key as String, fallback as String) as String {
        var value = source[key];
        return value instanceof String ? value : fallback;
    }

    private function asNumber(source as Dictionary, key as String, fallback as Number) as Number {
        var value = source[key];
        return value instanceof Number ? value : fallback;
    }
}
