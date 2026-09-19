import Toybox.Lang;
import Toybox.WatchUi;

// The keypad's geometry belongs to the view, so a tap is forwarded rather than
// interpreted here.
class PinDelegate extends WatchUi.BehaviorDelegate {

    private var _view as PinView;

    function initialize(view as PinView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    function onTap(event as WatchUi.ClickEvent) as Boolean {
        return _view.onTouch(event.getCoordinates());
    }

    // Choosing a PIN is something the wearer asked for and can change their
    // mind about, so back abandons it. Unlocking is not: there is nothing
    // behind that screen, and falling through leaves the app, which is the
    // only thing back could usefully do there.
    function onBack() as Boolean {
        if (_view.isSetting()) {
            return getApp().cancelPinSetup();
        }
        return false;
    }
}
