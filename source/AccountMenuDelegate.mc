import Toybox.Lang;
import Toybox.WatchUi;

class AccountMenuDelegate extends WatchUi.Menu2InputDelegate {

    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (id instanceof Number) {
            getApp().showCode(id);
        } else if (:refresh.equals(id)) {
            getApp().refreshFromMenu();
        }
    }
}
