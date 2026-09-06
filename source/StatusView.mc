import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

// A centred, word-wrapped message. Used for loading and for every error state.
class StatusView extends WatchUi.View {

    private var _message as String;

    function initialize(message as String) {
        View.initialize();
        _message = message;
    }

    function setMessage(message as String) as Void {
        _message = message;
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        var font = Graphics.FONT_SMALL;
        var lines = Text.wrap(dc, _message, font, dc.getWidth() * 3 / 4);
        var lineHeight = dc.getFontHeight(font);
        var y = dc.getHeight() / 2 - (lines.size() * lineHeight) / 2;

        for (var i = 0; i < lines.size(); i++) {
            dc.drawText(dc.getWidth() / 2, y + i * lineHeight, font, lines[i],
                Graphics.TEXT_JUSTIFY_CENTER);
        }
    }
}
