import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Timer;
import Toybox.WatchUi;

// Menu2 takes its light background from the device personality, so the list is
// drawn as a CustomMenu instead: dark to match the code screen, and easier on
// an AMOLED panel.
//
// It also drives the marquee. Individual items have no timer of their own, and
// on a touch device isFocused() is never true — there is no highlight to hang
// the animation off — so the menu ticks and every over-long label scrolls.
class AccountMenu extends WatchUi.CustomMenu {

    static const BACKGROUND = Graphics.COLOR_BLACK;
    static const FRAME_MS = 100;

    static var tick as Number = 0;

    // Set by any item that drew clipped text. When a whole pass sets nothing,
    // there is nothing to animate and the redraws stop until the list changes.
    static var scrolling as Boolean = false;

    private var _timer as Timer.Timer?;

    function initialize(itemHeight as Number) {
        // CustomMenu reserves a title band even when no title is supplied,
        // which pushes the first account down past the middle of the screen.
        // Zeroing it lets the list start at the top and fit a fourth row.
        CustomMenu.initialize(itemHeight, BACKGROUND, { :titleItemHeight => 0 });
    }

    function onShow() as Void {
        tick = 0;
        scrolling = true;
        _timer = new Timer.Timer();
        _timer.start(method(:onFrame), FRAME_MS, true);
    }

    function onHide() as Void {
        var timer = _timer;
        if (timer != null) {
            timer.stop();
            _timer = null;
        }
    }

    function onFrame() as Void {
        if (!scrolling) {
            return;
        }
        tick++;
        scrolling = false;
        WatchUi.requestUpdate();
    }
}

class AccountMenuItem extends WatchUi.CustomMenuItem {

    private const HOLD_FRAMES = 12;
    private const PIXELS_PER_FRAME = 2;

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

        // The top and bottom rows sit where the round screen is narrowest, so
        // labels are held to a width that survives there.
        var maxWidth = dc.getWidth() * 7 / 10;

        if (secondary == null) {
            var y = centreY - dc.getFontHeight(Graphics.FONT_SMALL) / 2;
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            label(dc, _primary, Graphics.FONT_SMALL, centreX, y, maxWidth);
            drawDivider(dc);
            return;
        }

        var primaryHeight = dc.getFontHeight(Graphics.FONT_SMALL);
        var secondaryHeight = dc.getFontHeight(Graphics.FONT_XTINY);
        var y = centreY - (primaryHeight + secondaryHeight) / 2;

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        label(dc, _primary, Graphics.FONT_SMALL, centreX, y, maxWidth);

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        label(dc, secondary, Graphics.FONT_XTINY, centreX, y + primaryHeight, maxWidth);

        drawDivider(dc);
    }

    // Centred if it fits, and scrolled within a clip if it does not.
    private function label(dc as Graphics.Dc, text as String, font as Graphics.FontType, centreX as Number, y as Number, maxWidth as Number) as Void {
        var width = dc.getTextWidthInPixels(text, font);
        if (width <= maxWidth) {
            dc.drawText(centreX, y, font, text, Graphics.TEXT_JUSTIFY_CENTER);
            return;
        }

        AccountMenu.scrolling = true;

        var left = centreX - maxWidth / 2;
        var height = dc.getFontHeight(font);
        dc.setClip(left, y, maxWidth, height);
        dc.drawText(left - offset(width - maxWidth), y, font, text, Graphics.TEXT_JUSTIFY_LEFT);
        dc.clearClip();
    }

    // Rest at the start, scroll to the end, rest again, then snap back. Easier
    // to read than a continuous loop, which never shows a settled beginning.
    private function offset(travel as Number) as Number {
        var steps = travel / PIXELS_PER_FRAME;
        var frame = AccountMenu.tick % (HOLD_FRAMES + steps + HOLD_FRAMES);

        if (frame < HOLD_FRAMES) {
            return 0;
        }
        if (frame < HOLD_FRAMES + steps) {
            return (frame - HOLD_FRAMES) * PIXELS_PER_FRAME;
        }
        return travel;
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
