import Toybox.Application;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

class OtpManagerApp extends Application.AppBase {

    private var _config as Config;
    private var _store as AccountStore;
    private var _api as OtpManagerApi;
    private var _statusView as StatusView?;

    function initialize() {
        AppBase.initialize();
        _config = new Config();
        _store = new AccountStore(_config);
        _api = new OtpManagerApi(_config);
    }

    function getInitialView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
        if (!_config.isComplete()) {
            return [status(Rez.Strings.NotConfigured), new WatchUi.BehaviorDelegate()];
        }

        // A cached list opens instantly and works with no phone nearby; the
        // Refresh item is there for when accounts have actually changed.
        if (_store.hasAccounts()) {
            return [buildMenu(), new AccountMenuDelegate()];
        }

        var view = status(Rez.Strings.Loading);
        _api.refresh(method(:onRefresh));
        return [view, new WatchUi.BehaviorDelegate()];
    }

    // Settings edited in Garmin Connect land here while the app is running.
    function onSettingsChanged() as Void {
        _config = new Config();
        _store = new AccountStore(_config);
        _api = new OtpManagerApi(_config);
    }

    function refreshFromMenu() as Void {
        var view = status(Rez.Strings.Loading);
        WatchUi.switchToView(view, new WatchUi.BehaviorDelegate(), WatchUi.SLIDE_IMMEDIATE);
        _api.refresh(method(:onRefresh));
    }

    function showCode(index as Number) as Void {
        var accounts = _store.getAccounts();
        if (index < 0 || index >= accounts.size()) {
            return;
        }
        WatchUi.pushView(new CodeView(accounts[index], _store.secretBox()),
            new WatchUi.BehaviorDelegate(), WatchUi.SLIDE_LEFT);
    }

    function onRefresh(result as OtpManagerApi.Result, payload as Dictionary?, message as String?) as Void {
        if (result != OtpManagerApi.RESULT_OK || payload == null) {
            report(explain(result, message));
            return;
        }

        _store.update(payload);

        if (!_store.hasAccounts()) {
            report(WatchUi.loadResource(Rez.Strings.NoAccounts) as String);
            return;
        }

        WatchUi.switchToView(buildMenu(), new AccountMenuDelegate(), WatchUi.SLIDE_IMMEDIATE);
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
