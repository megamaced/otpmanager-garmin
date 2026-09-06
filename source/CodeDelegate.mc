import Toybox.Lang;
import Toybox.WatchUi;

// The code screen replaces the list rather than stacking on top of it, so back
// has to put the list back explicitly. See OtpManagerApp for why nothing in
// this app is ever pushed.
class CodeDelegate extends WatchUi.BehaviorDelegate {

    function initialize() {
        BehaviorDelegate.initialize();
    }

    function onBack() as Boolean {
        return getApp().showListIfLoaded();
    }
}
