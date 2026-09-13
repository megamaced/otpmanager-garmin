import Toybox.Application;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

// Every screen change is a switchToView: nothing is ever pushed, so the view
// stack is always exactly one deep. A stale view left underneath a newer one is
// otherwise reachable with Back, and its menu ids would index the current store.
class OtpManagerApp extends Application.AppBase {

    private var _config as Config;
    private var _store as AccountStore;
    private var _api as OtpManagerApi;
    private var _statusView as StatusView?;

    // Bumped whenever the configuration is replaced. An in-flight refresh
    // carries the generation it began under, and is dropped if that is stale.
    private var _generation as Number = 0;

    // True from the moment a refresh starts until it succeeds or fails. While
    // it is set, the status screen is the only reachable screen, so a late
    // callback cannot land on top of something the wearer has navigated to.
    private var _refreshing as Boolean = false;

    // The salt and IV a pending seal will use. Decided once, because the key
    // the wearer is about to derive is only good for the salt it came from.
    private var _sealSalt as ByteArray = []b;
    private var _sealIv as ByteArray = []b;

    function initialize() {
        AppBase.initialize();
        _config = new Config();
        resumeUnlock();
        _store = new AccountStore(_config);
        _api = new OtpManagerApi(_config, _generation);
    }

    function getInitialView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
        return viewForState();
    }

    // Settings edited in Garmin Connect land here while the app is running. The
    // model is rebuilt, and the screen has to follow it — otherwise a menu, or
    // a code, from the previous configuration stays on display.
    function onSettingsChanged() as Void {
        _generation++;
        _refreshing = false;
        _config = new Config();
        _sealSalt = []b;
        resumeUnlock();
        _store = new AccountStore(_config);
        _api = new OtpManagerApi(_config, _generation);

        showFromState();
    }

    function refreshFromMenu() as Void {
        // Two chains would share this API instance's _hasPassword and _iv, and
        // could complete out of order.
        if (_refreshing) {
            return;
        }

        var view = status(Rez.Strings.Loading);
        WatchUi.switchToView(view, new StatusDelegate(), WatchUi.SLIDE_IMMEDIATE);
        beginRefresh();
    }

    // Used by StatusDelegate and CodeDelegate to get back to the list. Refused
    // mid-refresh: leaving the status screen then would let the completion
    // callback replace whatever the wearer had moved on to.
    function showListIfLoaded() as Boolean {
        if (_refreshing || !_store.isLoaded()) {
            return false;
        }
        showList();
        return true;
    }

    function showCode(index as Number) as Void {
        var accounts = _store.getAccounts();
        if (index < 0 || index >= accounts.size()) {
            return;
        }
        WatchUi.switchToView(new CodeView(accounts[index], _store.secretBox()),
            new CodeDelegate(), WatchUi.SLIDE_LEFT);
    }

    function onRefresh(generation as Number, result as OtpManagerApi.Result, payload as Dictionary?, message as String?) as Void {
        if (generation != _generation) {
            return;
        }

        _refreshing = false;

        if (result != OtpManagerApi.RESULT_OK || payload == null) {
            report(explain(result, message));
            return;
        }

        _store.update(payload);
        showList();
    }

    private function beginRefresh() as Void {
        _refreshing = true;
        _api.refresh(method(:onRefresh));
    }

    private function showList() as Void {
        WatchUi.switchToView(buildMenu(), new AccountMenuDelegate(), WatchUi.SLIDE_IMMEDIATE);
    }

    // A PIN entered on the keypad, with the key derived from it. Returns false
    // for a wrong one, which is the only answer the keypad needs: on success
    // the view is replaced here.
    function onPinEntered(typed as String, key as ByteArray) as Boolean {
        var pending = _config.pendingPin();
        if (!pending.equals("")) {
            return applySeal(typed, pending, key);
        }

        var blob = _config.sealedBlob();
        if (blob == null) {
            return false;
        }

        var credentials = blob.open(key);
        if (credentials == null) {
            return false;
        }

        PinLock.remember(key);
        _config.unlock(credentials);
        _store = new AccountStore(_config);
        _api = new OtpManagerApi(_config, _generation);

        showFromState();
        return true;
    }

    // The first launch after a PIN was set in Garmin Connect. The wearer types
    // it again here, which is what makes replacing the plaintext safe — and
    // there is no blob to try the key against yet, so the digits are compared.
    private function applySeal(typed as String, pending as String, key as ByteArray) as Boolean {
        if (!typed.equals(pending)) {
            return false;
        }

        var blob = Sealed.sealWithKey(_config.appPassword, _config.otpPassword,
            pending.length(), _sealSalt, _sealIv, key);
        if (blob == null) {
            return false;
        }

        _config.completeSeal(blob);
        PinLock.remember(key);

        showFromState();
        return true;
    }

    private function showFromState() as Void {
        var next = viewForState();
        WatchUi.switchToView(next[0], next[1] as WatchUi.InputDelegates, WatchUi.SLIDE_IMMEDIATE);
    }

    // An unlock from an earlier launch that is still inside its 24 hours and
    // was worn throughout. Nothing happens on a build with no PIN.
    private function resumeUnlock() as Void {
        var blob = _config.sealedBlob();
        if (blob == null) {
            return;
        }

        var key = PinLock.recall();
        if (key == null) {
            return;
        }

        var credentials = blob.open(key);
        if (credentials == null) {
            // The seal was replaced under a PIN this key does not answer to.
            PinLock.forget();
            return;
        }
        _config.unlock(credentials);
    }

    private function viewForState() as [WatchUi.Views, WatchUi.InputDelegates] {
        if (!_config.hasServer()) {
            return [status(Rez.Strings.NotConfigured), new StatusDelegate()];
        }
        if (!_config.isSecure()) {
            return [status(Rez.Strings.InsecureUrl), new StatusDelegate()];
        }
        // A PIN waiting to be applied comes first: until it is, the passwords
        // it is meant to protect are sitting in the properties in the clear.
        var pending = _config.pendingPin();
        if (!pending.equals("")) {
            if (!_config.canSeal()) {
                return [status(Rez.Strings.BadPin), new StatusDelegate()];
            }
            if (_sealSalt.size() == 0) {
                _sealSalt = Sealed.salt();
                _sealIv = Sealed.iv();
            }
            return keypad(pending.length(), Sealed.ITERATIONS, _sealSalt);
        }

        // Sealed and not yet opened: nothing else can be reached from here, and
        // the credentials are not in memory to be reached with.
        var blob = _config.sealedBlob();
        if (blob != null && !_config.isComplete()) {
            return keypad(blob.pinLength, blob.iterations, blob.salt);
        }

        if (!_config.isComplete()) {
            return [status(Rez.Strings.NotConfigured), new StatusDelegate()];
        }

        // A cached list opens instantly and works with no phone nearby; the
        // Refresh row is there for when accounts have actually changed. An
        // empty vault is a loaded state too, and must not re-fetch every launch.
        if (_store.isLoaded()) {
            return [buildMenu(), new AccountMenuDelegate()];
        }

        var view = status(Rez.Strings.Loading);
        beginRefresh();
        return [view, new StatusDelegate()];
    }

    private function keypad(pinLength as Number, iterations as Number, salt as ByteArray) as [WatchUi.Views, WatchUi.InputDelegates] {
        var view = new PinView(pinLength, iterations, salt);
        return [view, new PinDelegate(view)];
    }

    // No title: on a round screen a title band costs a whole list row, and the
    // launcher already said which app this is.
    private function buildMenu() as WatchUi.CustomMenu {
        var menu = new AccountMenu(System.getDeviceSettings().screenHeight / 4);
        var accounts = _store.getAccounts();

        for (var i = 0; i < accounts.size(); i++) {
            var account = accounts[i];
            var issuer = account["issuer"] as String;
            var name = account["name"] as String;
            var hasIssuer = !issuer.equals("") && !issuer.equals(name);

            menu.addItem(new AccountMenuItem(i, hasIssuer ? issuer : name, hasIssuer ? name : null));
        }

        // Without this the empty vault is a lone Refresh row with no explanation.
        if (_store.isEmpty()) {
            menu.addItem(new AccountMenuItem(
                :none, WatchUi.loadResource(Rez.Strings.NoAccountsRow) as String, null));
        }

        menu.addItem(new AccountMenuItem(
            :refresh, WatchUi.loadResource(Rez.Strings.Refresh) as String, null));

        return menu;
    }

    // The status view is only on screen when a refresh was started from it.
    private function report(message as String) as Void {
        var view = _statusView;
        if (view != null) {
            view.setMessage(message);
        }
    }

    private function status(resource as ResourceId) as StatusView {
        _statusView = new StatusView(WatchUi.loadResource(resource) as String);
        return _statusView;
    }

    private function explain(result as OtpManagerApi.Result, message as String?) as String {
        if (result == OtpManagerApi.RESULT_NOT_CONFIGURED) {
            return WatchUi.loadResource(Rez.Strings.NotConfigured) as String;
        }
        if (result == OtpManagerApi.RESULT_AUTH_FAILED) {
            return WatchUi.loadResource(Rez.Strings.AuthFailed) as String;
        }
        if (result == OtpManagerApi.RESULT_BAD_OTP_PASSWORD) {
            return WatchUi.loadResource(Rez.Strings.DecryptFailed) as String;
        }
        return message != null ? message : WatchUi.loadResource(Rez.Strings.Unreachable) as String;
    }
}

function getApp() as OtpManagerApp {
    return Application.getApp() as OtpManagerApp;
}
