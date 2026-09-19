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

    // A sign-in waiting on the phone. Polling outlives any view, so leaving the
    // screen has to cancel it rather than let it report into a later one.
    private var _login as NcLogin?;

    // Why the last sign-in did not finish, shown under the row that retries it.
    private var _loginError as String?;

    // The salt and IV a pending seal will use. Decided once, because the key
    // the wearer is about to derive is only good for the salt it came from.
    private var _sealSalt as ByteArray = []b;
    private var _sealIv as ByteArray = []b;

    function initialize() {
        AppBase.initialize();
        discardUnboundCredentials();
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
        cancelSignIn();
        rebuild();
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
        cancelSignIn();
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

    // Nextcloud's Login Flow v2, which is what replaced typing a sixty-
    // character app password into a phone. See NcLogin for why it is that and
    // not an OAuth exchange.
    function signIn() as Void {
        if (_login != null) {
            return;
        }

        _loginError = null;
        var view = status(Rez.Strings.SignInWaiting);
        WatchUi.switchToView(view, new StatusDelegate(), WatchUi.SLIDE_IMMEDIATE);

        var login = new NcLogin(_config.serverUrl);
        _login = login;
        login.begin(method(:onSignedIn));
    }

    function onSignedIn(result as NcLogin.Result, credentials as SignIn?) as Void {
        if (_login == null) {
            return;
        }
        _login = null;

        if (result != NcLogin.LOGIN_OK || credentials == null) {
            _loginError = explainLogin(result);
            WatchUi.switchToView(buildSignInMenu(), new AccountMenuDelegate(false),
                WatchUi.SLIDE_IMMEDIATE);
            return;
        }

        // Written before the PIN is offered rather than after it is chosen. The
        // web sign-in is the slow part and should not have to be repeated
        // because the wearer put the watch down at the keypad; what this costs
        // is a plaintext app password in watch storage until a PIN replaces it,
        // which is exactly what a build with no PIN keeps there anyway.
        CredentialStore.storeSignIn(credentials.server, credentials.username, credentials.appPassword);
        rebuild();

        // Nothing to seal until the vault password is there too, and offering a
        // PIN that cannot be applied yet is a dead end. The state screen says
        // what is missing, and Options offers the PIN once it is not.
        if (!_config.isComplete()) {
            showFromState();
            return;
        }

        WatchUi.switchToView(buildPinChoiceMenu(), new AccountMenuDelegate(false),
            WatchUi.SLIDE_IMMEDIATE);
    }

    function beginPinSetup() as Void {
        _sealSalt = Sealed.salt();
        _sealIv = Sealed.iv();

        var view = new PinView(0, Sealed.ITERATIONS, _sealSalt, true);
        WatchUi.switchToView(view, new PinDelegate(view), WatchUi.SLIDE_IMMEDIATE);
    }

    // Back from the keypad. Nothing has been sealed, so the credentials are
    // where they were and the app carries on without a PIN.
    function cancelPinSetup() as Boolean {
        _sealSalt = []b;
        showFromState();
        return true;
    }

    function keepNoPin() as Void {
        showFromState();
    }

    // A new PIN, typed twice and turned into a key. Sealing here is what takes
    // the app password out of watch storage and the vault password out of the
    // settings screen; from this point neither exists anywhere in the clear.
    function onPinChosen(typed as String, key as ByteArray) as Boolean {
        var credentials = _config.credentials();
        if (!credentials.isComplete() || !Sealed.isPin(typed)) {
            return false;
        }

        var blob = Sealed.sealWithKey(credentials, typed.length(), _sealSalt, _sealIv, key);
        if (blob == null) {
            return false;
        }

        CredentialStore.storeSeal(blob);
        _config.clearPendingOtpPassword();
        PinLock.remember(key);

        // Any cache written before the PIN existed holds its secrets as the
        // server sent them, which for a passwordless vault means in the clear.
        // Re-writing it under the new key is what stops the PIN arriving too
        // late to protect what is already stored.
        _config.setLocalKey(key);
        _store.persist();

        showFromState();
        return true;
    }

    // A PIN entered on the keypad, with the key derived from it. Returns false
    // for a wrong one, which is the only answer the keypad needs: on success
    // the view is replaced here.
    function onPinEntered(typed as String, key as ByteArray) as Boolean {
        var blob = _config.sealedBlob();
        if (blob == null) {
            return false;
        }

        var credentials = blob.open(key);
        if (credentials == null) {
            return false;
        }

        credentials = applyPendingOtpPassword(blob, credentials as Credentials, key);

        PinLock.remember(key);
        _config.unlock(credentials as Credentials);
        // Before the store is built: restoring the cache needs this key to
        // read back any secret that was encrypted locally under it.
        _config.setLocalKey(key);
        _store = new AccountStore(_config);
        _api = new OtpManagerApi(_config, _generation);

        showFromState();
        return true;
    }

    function showOptions() as Void {
        WatchUi.switchToView(buildOptionsMenu(), new AccountMenuDelegate(true),
            WatchUi.SLIDE_LEFT);
    }

    // Forgets the app password rather than revoking it: only Nextcloud can do
    // that, under Settings, Security, Devices & sessions — which is worth doing
    // as well if the reason for signing out is that the watch was lost.
    function signOut() as Void {
        cancelSignIn();
        CredentialStore.clear();
        PinLock.forget();
        AccountStore.clearCache();

        _loginError = null;
        rebuild();
        showFromState();
    }

    // A vault password typed into the settings screen while a seal already held
    // one. Re-sealed under the same PIN — the salt is the blob's, so the key
    // just derived still opens it — and cleared from the settings screen again.
    private function applyPendingOtpPassword(blob as SealedBlob, credentials as Credentials, key as ByteArray) as Credentials {
        var pending = _config.pendingOtpPassword();
        if (pending.equals("")) {
            return credentials;
        }

        var updated = Credentials.replacingOtpPassword(credentials, pending);
        if (updated != null) {
            var resealed = Sealed.sealWithKey(updated as Credentials, blob.pinLength,
                blob.salt, Sealed.iv(), key);
            if (resealed == null) {
                return credentials;
            }

            CredentialStore.storeSeal(resealed);
            credentials = updated as Credentials;
        }

        _config.clearPendingOtpPassword();
        return credentials;
    }

    private function cancelSignIn() as Void {
        var login = _login;
        if (login != null) {
            login.cancel();
            _login = null;
        }
    }

    private function rebuild() as Void {
        _generation++;
        _refreshing = false;
        _config = new Config();
        _sealSalt = []b;
        resumeUnlock();
        _store = new AccountStore(_config);
        _api = new OtpManagerApi(_config, _generation);
    }

    private function beginRefresh() as Void {
        _refreshing = true;
        _api.refresh(method(:onRefresh));
    }

    private function showList() as Void {
        WatchUi.switchToView(buildMenu(), new AccountMenuDelegate(false), WatchUi.SLIDE_IMMEDIATE);
    }

    private function showFromState() as Void {
        var next = viewForState();
        WatchUi.switchToView(next[0], next[1] as WatchUi.InputDelegates, WatchUi.SLIDE_IMMEDIATE);
    }

    // Credentials stored by a version of the app that did not record which
    // server issued them. Signing in again is what binds them, and it is two
    // taps; the alternative is trusting the settings screen to still name the
    // host they came from, which is the assumption the binding exists to stop
    // the app making. The cache goes with them — it was fetched with them.
    //
    // A sideload is not this: nothing there was ever issued, so a seal it made
    // on the watch names no server and is meant to.
    private function discardUnboundCredentials() as Void {
        if (!CredentialStore.hasUnboundCredentials()) {
            return;
        }

        CredentialStore.clear();
        PinLock.forget();
        AccountStore.clearCache();
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

        // The same check the keypad path makes. Without it, a vault password
        // typed into the settings screen is ignored for as long as the
        // remembered unlock keeps holding — which is up to 24 hours of
        // refreshes failing while the new value sits there looking applied.
        _config.unlock(applyPendingOtpPassword(blob, credentials, key));
        _config.setLocalKey(key);
    }

    private function viewForState() as [WatchUi.Views, WatchUi.InputDelegates] {
        if (!_config.hasServer()) {
            return [status(Rez.Strings.NotConfigured), new StatusDelegate()];
        }
        if (!_config.isSecure()) {
            return [status(Rez.Strings.InsecureUrl), new StatusDelegate()];
        }

        // Sealed and not yet opened: nothing else can be reached from here, and
        // the credentials are not in memory to be reached with.
        var blob = _config.sealedBlob();
        if (blob != null && !_config.isComplete()) {
            var view = new PinView(blob.pinLength, blob.iterations, blob.salt, false);
            return [view, new PinDelegate(view)];
        }

        // A seal that will not parse is one made by an older version of this
        // app, before the login name was part of it. Signing in again is the
        // migration, and it is two taps.
        //
        // The same screen catches a server that has been pointed somewhere
        // else since the credentials were issued. They belong to the old host
        // and must not be offered to the new one.
        if (!_config.hasCredentials() || !_config.credentialsMatchServer()) {
            return [buildSignInMenu(), new AccountMenuDelegate(false)];
        }

        if (!_config.isComplete()) {
            return [status(Rez.Strings.NeedOtpPassword), new StatusDelegate()];
        }

        // A cached list opens instantly and works with no phone nearby; the
        // Refresh row is there for when accounts have actually changed. An
        // empty vault is a loaded state too, and must not re-fetch every launch.
        if (_store.isLoaded()) {
            return [buildMenu(), new AccountMenuDelegate(false)];
        }

        var loading = status(Rez.Strings.Loading);
        beginRefresh();
        return [loading, new StatusDelegate()];
    }

    // No title: on a round screen a title band costs a whole list row, and the
    // launcher already said which app this is.
    private function buildMenu() as WatchUi.CustomMenu {
        var menu = newMenu();
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
            menu.addItem(new AccountMenuItem(:none, text(Rez.Strings.NoAccountsRow), null));
        }

        menu.addItem(new AccountMenuItem(:refresh, text(Rez.Strings.Refresh), null));
        menu.addItem(new AccountMenuItem(:options, text(Rez.Strings.Options), null));

        return menu;
    }

    private function buildSignInMenu() as WatchUi.CustomMenu {
        var menu = newMenu();
        menu.addItem(new AccountMenuItem(:signIn, text(Rez.Strings.SignIn),
            _loginError != null ? _loginError : text(Rez.Strings.SignInSubtitle)));
        return menu;
    }

    // Offered once, straight after signing in. Declining is a real answer, so
    // it is a row of its own rather than something to guess at with Back.
    private function buildPinChoiceMenu() as WatchUi.CustomMenu {
        var menu = newMenu();
        menu.addItem(new AccountMenuItem(:setPin, text(Rez.Strings.PinSet),
            text(Rez.Strings.PinSetSubtitle)));
        menu.addItem(new AccountMenuItem(:noPin, text(Rez.Strings.PinSkip),
            text(Rez.Strings.PinSkipSubtitle)));
        return menu;
    }

    private function buildOptionsMenu() as WatchUi.CustomMenu {
        var menu = newMenu();
        menu.addItem(new AccountMenuItem(:setPin,
            text(_config.isSealed() ? Rez.Strings.PinChange : Rez.Strings.PinSet), null));
        menu.addItem(new AccountMenuItem(:signOut, text(Rez.Strings.SignOut), null));
        return menu;
    }

    private function newMenu() as AccountMenu {
        return new AccountMenu(System.getDeviceSettings().screenHeight / 4);
    }

    private function text(resource as ResourceId) as String {
        return WatchUi.loadResource(resource) as String;
    }

    // The status view is only on screen when a refresh was started from it.
    private function report(message as String) as Void {
        var view = _statusView;
        if (view != null) {
            view.setMessage(message);
        }
    }

    private function status(resource as ResourceId) as StatusView {
        _statusView = new StatusView(text(resource));
        return _statusView;
    }

    private function explain(result as OtpManagerApi.Result, message as String?) as String {
        if (result == OtpManagerApi.RESULT_NOT_CONFIGURED) {
            return text(Rez.Strings.NotConfigured);
        }
        if (result == OtpManagerApi.RESULT_AUTH_FAILED) {
            return text(Rez.Strings.AuthFailed);
        }
        if (result == OtpManagerApi.RESULT_BAD_OTP_PASSWORD) {
            return text(Rez.Strings.DecryptFailed);
        }
        return message != null ? message : text(Rez.Strings.Unreachable);
    }

    private function explainLogin(result as NcLogin.Result) as String {
        if (result == NcLogin.LOGIN_NO_PHONE) {
            return text(Rez.Strings.NoPhone);
        }
        if (result == NcLogin.LOGIN_TIMED_OUT) {
            return text(Rez.Strings.SignInTimedOut);
        }
        if (result == NcLogin.LOGIN_WRONG_SERVER) {
            return text(Rez.Strings.SignInWrongServer);
        }
        return text(Rez.Strings.SignInFailed);
    }
}

function getApp() as OtpManagerApp {
    return Application.getApp() as OtpManagerApp;
}
