import Toybox.Lang;
import Toybox.WatchUi;

// The keypad's geometry belongs to the view, so a tap is forwarded rather than
// interpreted here. Back is left alone: from the lock screen it leaves the app,
// which is the only thing it could usefully do.
class PinDelegate extends WatchUi.BehaviorDelegate {

    private var _view as PinView;

    function initialize(view as PinView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    function onTap(event as WatchUi.ClickEvent) as Boolean {
        return _view.onTouch(event.getCoordinates());
    }
}
