import Toybox.Application;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

class OtpManagerApp extends Application.AppBase {

    private var _config as Config;
    private var _store as AccountStore;
    private var _api as OtpManagerApi;
    private var _statusView as StatusView?;

    // Bumped whenever the configuration is replaced. An in-flight refresh
    // carries the generation it began under, and is dropped if that is stale.
    private var _generation as Number = 0;

    function initialize() {
        AppBase.initialize();
        _config = new Config();
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
        _config = new Config();
        _store = new AccountStore(_config);
        _api = new OtpManagerApi(_config, _generation);

        var next = viewForState();
        WatchUi.switchToView(next[0], next[1] as WatchUi.InputDelegates, WatchUi.SLIDE_IMMEDIATE);
    }

    function refreshFromMenu() as Void {
        var view = status(Rez.Strings.Loading);
        WatchUi.switchToView(view, new StatusDelegate(), WatchUi.SLIDE_IMMEDIATE);
        _api.refresh(method(:onRefresh));
    }

    // Used by StatusDelegate to get back to a cached list after an error.
    function showListIfLoaded() as Boolean {
        if (!_store.isLoaded()) {
            return false;
        }
        WatchUi.switchToView(buildMenu(), new AccountMenuDelegate(), WatchUi.SLIDE_IMMEDIATE);
        return true;
    }

    function showCode(index as Number) as Void {
        var accounts = _store.getAccounts();
        if (index < 0 || index >= accounts.size()) {
            return;
        }
        WatchUi.pushView(new CodeView(accounts[index], _store.secretBox()),
            new WatchUi.BehaviorDelegate(), WatchUi.SLIDE_LEFT);
    }

    function onRefresh(generation as Number, result as OtpManagerApi.Result, payload as Dictionary?, message as String?) as Void {
        if (generation != _generation) {
            return;
        }

        if (result != OtpManagerApi.RESULT_OK || payload == null) {
            report(explain(result, message));
            return;
        }

        _store.update(payload);
        WatchUi.switchToView(buildMenu(), new AccountMenuDelegate(), WatchUi.SLIDE_IMMEDIATE);
    }

    private function viewForState() as [WatchUi.Views, WatchUi.InputDelegates] {
        if (!_config.isComplete()) {
            return [status(Rez.Strings.NotConfigured), new StatusDelegate()];
        }
        if (!_config.isSecure()) {
            return [status(Rez.Strings.InsecureUrl), new StatusDelegate()];
        }

        // A cached list opens instantly and works with no phone nearby; the
        // Refresh row is there for when accounts have actually changed. An
        // empty vault is a loaded state too, and must not re-fetch every launch.
        if (_store.isLoaded()) {
            return [buildMenu(), new AccountMenuDelegate()];
        }

        var view = status(Rez.Strings.Loading);
        _api.refresh(method(:onRefresh));
        return [view, new StatusDelegate()];
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
        if (accounts.size() == 0) {
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
