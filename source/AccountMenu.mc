import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

// Menu2 takes its light background from the device personality, so the list is
// drawn as a CustomMenu instead: dark to match the code screen, and easier on
// an AMOLED panel.
class AccountMenu extends WatchUi.CustomMenu {

    static const BACKGROUND = Graphics.COLOR_BLACK;

    function initialize(itemHeight as Number) {
        CustomMenu.initialize(itemHeight, BACKGROUND, {});
    }
}

class AccountMenuItem extends WatchUi.CustomMenuItem {

    private var _primary as String;
    private var _secondary as String?;

    function initialize(identifier as Object, primary as String, secondary as String?) {
        CustomMenuItem.initialize(identifier, {});
        _primary = primary;
        _secondary = secondary;
    }

    function draw(dc as Graphics.Dc) as Void {
        var focused = isFocused();
        dc.setColor(focused ? Graphics.COLOR_DK_GRAY : AccountMenu.BACKGROUND,
            focused ? Graphics.COLOR_DK_GRAY : AccountMenu.BACKGROUND);
        dc.clear();

        var centreX = dc.getWidth() / 2;
        var centreY = dc.getHeight() / 2;
        var secondary = _secondary;

        if (secondary == null) {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(centreX, centreY - dc.getFontHeight(Graphics.FONT_SMALL) / 2,
                Graphics.FONT_SMALL, _primary, Graphics.TEXT_JUSTIFY_CENTER);
            drawDivider(dc);
            return;
        }

        var primaryHeight = dc.getFontHeight(Graphics.FONT_SMALL);
        var secondaryHeight = dc.getFontHeight(Graphics.FONT_XTINY);
        var y = centreY - (primaryHeight + secondaryHeight) / 2;

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(centreX, y, Graphics.FONT_SMALL, _primary, Graphics.TEXT_JUSTIFY_CENTER);

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(centreX, y + primaryHeight, Graphics.FONT_XTINY, secondary,
            Graphics.TEXT_JUSTIFY_CENTER);

        drawDivider(dc);
    }

    // Rows are two lines tall, so they need a rule between them to read as
    // separate entries.
    private function drawDivider(dc as Graphics.Dc) as Void {
        var inset = dc.getWidth() / 5;
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(1);
        dc.drawLine(inset, dc.getHeight() - 1, dc.getWidth() - inset, dc.getHeight() - 1);
    }
}
