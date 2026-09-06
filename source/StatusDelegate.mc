import Toybox.Lang;
import Toybox.WatchUi;

// Back from a status screen normally leaves the app. When a cached account list
// is still in memory — a refresh that failed, say — back returns to it instead,
// so a transient error does not strand the wearer away from working codes.
class StatusDelegate extends WatchUi.BehaviorDelegate {

    function initialize() {
        BehaviorDelegate.initialize();
    }

    function onBack() as Boolean {
        return getApp().showListIfLoaded();
    }

    function onSelect() as Boolean {
        return getApp().showListIfLoaded();
    }
}
