import Toybox.Authentication;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.Timer;
import Toybox.WatchUi;

// Nextcloud Login Flow v2, driven from the watch.
//
//   POST /index.php/login/v2   a login URL for the phone, and a poll token
//   the phone browser          the wearer signs in and grants access
//   POST /login/v2/poll        404 until that happens, then once a 200 with
//                              the login name and a fresh app password
//
// The browser is opened with Authentication.makeOAuthRequest, which is the only
// way a Connect IQ app can put a URL in front of the wearer at all. This is not
// an OAuth exchange: nothing ever redirects to RESULT_URL, and the answer
// arrives on the poll rather than in an OAuth message. The result URL is
// supplied because the API demands one.
//
// Nextcloud's own OAuth2 provider would fit makeOAuthRequest more literally and
// is the worse trade. It has no PKCE, so the client secret would have to ship
// inside the .prg; its tokens are unscoped and expire hourly, which this app
// has nowhere to put; and Garmin Connect Mobile is known to overwrite
// redirect_uri with one of its own. What Login Flow v2 returns instead is an
// ordinary Nextcloud app password: revocable on its own, good until it is
// revoked, and exactly what the rest of the app already authenticates with.
class NcLogin {

    enum Result {
        LOGIN_OK,
        LOGIN_FAILED,
        LOGIN_TIMED_OUT,
        LOGIN_NO_PHONE
    }

    // Garmin Connect Mobile has to be opened, tapped and typed into, so the
    // first answer is never quick. Nextcloud keeps the login token for twenty
    // minutes; nobody stands over a phone for that long, and polling that whole
    // time over BLE is not free.
    const POLL_MS = 3000;
    const TIMEOUT_MS = 300000;

    // Named by Garmin for the Authentication module. Nothing reaches it here.
    const RESULT_URL = "connectiq://oauth";

    private var _serverUrl as String;
    private var _callback as (Method(result as Result, credentials as SignIn?) as Void)?;

    private var _token as String = "";
    private var _endpoint as String = "";
    private var _timer as Timer.Timer?;
    private var _elapsed as Number = 0;

    // One poll in flight at a time. A response slower than the interval would
    // otherwise stack requests up behind it for as long as it took.
    private var _polling as Boolean = false;
    private var _done as Boolean = false;

    function initialize(serverUrl as String) {
        _serverUrl = serverUrl;
    }

    function begin(callback as Method(result as Result, credentials as SignIn?) as Void) as Void {
        _callback = callback;

        Communications.makeWebRequest(
            _serverUrl + "/index.php/login/v2",
            {},
            {
                :method => Communications.HTTP_REQUEST_METHOD_POST,
                :headers => {
                    "Accept" => "application/json",
                    "Content-Type" => Communications.REQUEST_CONTENT_TYPE_URL_ENCODED
                },
                :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
            },
            method(:onStarted)
        );
    }

    // Leaving the sign-in screen stops the polling. Without this the timer
    // outlives the view that started it and reports into a screen the wearer
    // has already navigated away from.
    function cancel() as Void {
        _done = true;
        stop();
    }

    function onStarted(responseCode as Number, data as Dictionary or String or Null) as Void {
        if (_done) {
            return;
        }
        if (responseCode != 200 || !(data instanceof Dictionary)) {
            report(resultFor(responseCode), null);
            return;
        }

        var poll = data["poll"];
        var login = data["login"];
        if (!(poll instanceof Dictionary) || !(login instanceof String)) {
            report(LOGIN_FAILED, null);
            return;
        }

        var token = poll["token"];
        var endpoint = poll["endpoint"];
        if (!(token instanceof String) || !(endpoint instanceof String)) {
            report(LOGIN_FAILED, null);
            return;
        }

        _token = token;
        _endpoint = endpoint;

        if (!openOnPhone(login)) {
            report(LOGIN_FAILED, null);
            return;
        }
        startPolling();
    }

    function onPoll(responseCode as Number, data as Dictionary or String or Null) as Void {
        _polling = false;
        if (_done) {
            return;
        }

        // Not signed in yet. This is the answer almost every time.
        if (responseCode == 404) {
            return;
        }

        // A dropped connection mid-flow is not fatal: the phone is busy showing
        // a browser, and the token is good for twenty minutes. Keep polling and
        // let the timeout decide.
        if (responseCode != 200) {
            return;
        }

        var credentials = signInFrom(data);
        if (credentials == null) {
            report(LOGIN_FAILED, null);
            return;
        }

        report(LOGIN_OK, credentials);
    }

    // The only interesting part of a poll response, and the only part with no
    // network in the way of testing it. A 200 that does not carry both fields
    // is a failure rather than something to keep polling through: the token is
    // spent, because Nextcloud answers a successful poll exactly once.
    static function signInFrom(data as Dictionary or String or Null) as SignIn? {
        if (!(data instanceof Dictionary)) {
            return null;
        }

        var loginName = data["loginName"];
        var appPassword = data["appPassword"];
        if (!(loginName instanceof String) || !(appPassword instanceof String)
            || loginName.equals("") || appPassword.equals("")) {
            return null;
        }

        return new SignIn(loginName, appPassword);
    }

    function onTick() as Void {
        if (_done) {
            return;
        }

        _elapsed += POLL_MS;
        if (_elapsed >= TIMEOUT_MS) {
            report(LOGIN_TIMED_OUT, null);
            return;
        }

        if (_polling) {
            return;
        }
        _polling = true;

        Communications.makeWebRequest(
            _endpoint,
            { "token" => _token },
            {
                :method => Communications.HTTP_REQUEST_METHOD_POST,
                :headers => {
                    "Accept" => "application/json",
                    "Content-Type" => Communications.REQUEST_CONTENT_TYPE_URL_ENCODED
                },
                :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
            },
            method(:onPoll)
        );
    }

    // The OAuth message is registered for and then ignored. Login Flow v2 never
    // redirects anywhere this app can see, so the message says only that the
    // wearer closed the browser — which proves nothing either way, because the
    // grant may already have been given. The poll is the authority.
    function onOAuthMessage(message as Authentication.OAuthMessage) as Void {
    }

    private function openOnPhone(login as String) as Boolean {
        if (!(Authentication has :makeOAuthRequest)) {
            return false;
        }

        try {
            Authentication.registerForOAuthMessages(method(:onOAuthMessage));
            Authentication.makeOAuthRequest(
                login,
                {},
                RESULT_URL,
                Authentication.OAUTH_RESULT_TYPE_URL,
                {}
            );
        } catch (e) {
            return false;
        }
        return true;
    }

    private function startPolling() as Void {
        var timer = new Timer.Timer();
        timer.start(method(:onTick), POLL_MS, true);
        _timer = timer;
    }

    private function stop() as Void {
        var timer = _timer;
        if (timer != null) {
            timer.stop();
            _timer = null;
        }
    }

    // Every exit runs through here, so the timer is stopped exactly once and a
    // late callback cannot report a second time.
    private function report(result as Result, credentials as SignIn?) as Void {
        _done = true;
        stop();

        var callback = _callback;
        _callback = null;
        if (callback != null) {
            callback.invoke(result, credentials);
        }
    }

    private function resultFor(responseCode as Number) as Result {
        if (responseCode == Communications.BLE_CONNECTION_UNAVAILABLE
            || responseCode == Communications.BLE_HOST_TIMEOUT) {
            return LOGIN_NO_PHONE;
        }
        return LOGIN_FAILED;
    }
}

// What a completed sign-in yields. The login name is Nextcloud's, not the
// wearer's guess at it — on a server that provisions through OIDC it is often
// an email address, and getting it wrong is the commonest way to be told the
// app password is bad.
class SignIn {

    var username as String;
    var appPassword as String;

    function initialize(username as String, appPassword as String) {
        self.username = username;
        self.appPassword = appPassword;
    }
}
