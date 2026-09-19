import Toybox.Lang;
import Toybox.WatchUi;

// One delegate behind every list in the app: the accounts, the sign-in prompt,
// the choice of PIN and the options. A row carries either an account index or a
// symbol naming what it does.
class AccountMenuDelegate extends WatchUi.Menu2InputDelegate {

    private var _backToList as Boolean;

    function initialize(backToList as Boolean) {
        Menu2InputDelegate.initialize();
        _backToList = backToList;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (id instanceof Number) {
            getApp().showCode(id);
            return;
        }

        if (:refresh.equals(id)) {
            getApp().refreshFromMenu();
        } else if (:signIn.equals(id)) {
            getApp().signIn();
        } else if (:setPin.equals(id)) {
            getApp().beginPinSetup();
        } else if (:noPin.equals(id)) {
            getApp().keepNoPin();
        } else if (:options.equals(id)) {
            getApp().showOptions();
        } else if (:signOut.equals(id)) {
            getApp().signOut();
        }
    }

    // Overriding onBack replaces the inherited pop, so the fall-through has to
    // do it here. Nothing is ever pushed, so popping leaves the app — which is
    // the right answer everywhere except the options list.
    function onBack() as Void {
        if (_backToList && getApp().showListIfLoaded()) {
            return;
        }
        WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
    }
}
