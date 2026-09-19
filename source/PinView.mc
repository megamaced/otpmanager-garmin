import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

// The PIN keypad, and the progress ring shown while the key is derived from
// what was typed. Laid out in fractions of the screen so the same code fits a
// 390 and a 454 pixel round display, and drawn without ever setting a clip
// region — see the SDK notes for what a leaked clip does to the next view.
//
// It does two jobs. Unlocking knows the length from the blob header, so the
// last digit is the only signal it needs and there is no confirm key. Choosing
// a new PIN knows nothing, so it has one: the dead bottom-left cell, which on
// the unlock screen is a corner nobody can reach anyway.
class PinView extends WatchUi.View {

    // The bottom row's outer corners fall outside the glass on a round display.
    // Its digit centres do not, and a corner nobody can reach costs nothing.
    private const MESSAGE_Y = 0.05;
    private const DOTS_Y = 0.13;
    private const GRID_TOP = 0.21;
    private const GRID_BOTTOM = 0.90;
    private const GRID_LEFT = 0.145;
    private const GRID_RIGHT = 0.855;

    private const BACKSPACE = -1;
    private const CONFIRM = -2;

    // Rounds of SHA-256 per tick. Small enough that no single block of
    // computation can trip the watchdog, large enough to finish the whole
    // derivation in about a second.
    private const ROUNDS_PER_TICK = 250;
    private const TICK_MS = 25;

    // Everything the keypad needs to turn digits into a key, and nothing about
    // what the key is then for: the same screen unlocks an existing seal and
    // creates a new one.
    private var _pinLength as Number;
    private var _iterations as Number;
    private var _salt as ByteArray;
    private var _setting as Boolean;

    private var _width as Number;
    private var _height as Number;

    private var _entered as String = "";

    // The first of the two entries a new PIN is typed as. Null while the first
    // one is still being typed, which is also what the prompt is chosen on.
    private var _first as String? = null;

    // Shown in red, and cleared by the next key. Null the rest of the time.
    private var _notice as String? = null;

    // Non-null only while a key is being derived, which is also the window in
    // which the keypad ignores taps.
    private var _derivation as KeyDerivation?;
    private var _timer as Timer.Timer?;

    function initialize(pinLength as Number, iterations as Number, salt as ByteArray,
                        setting as Boolean) {
        View.initialize();
        _pinLength = pinLength;
        _iterations = iterations;
        _salt = salt;
        _setting = setting;

        var settings = System.getDeviceSettings();
        _width = settings.screenWidth;
        _height = settings.screenHeight;
    }

    // Back means different things on the two screens, and only the view knows
    // which one this is.
    function isSetting() as Boolean {
        return _setting;
    }

    // Called by PinDelegate, which has the touch events but none of the layout.
    function onTouch(coordinates as [Number, Number]) as Boolean {
        if (_derivation != null) {
            return true;
        }

        var cell = cellAt(coordinates[0], coordinates[1]);
        if (cell != null) {
            press(cell);
        }
        return true;
    }

    function onHide() as Void {
        stop();
        _derivation = null;
        _entered = "";
        _first = null;
    }

    function onTick() as Void {
        var derivation = _derivation;
        if (derivation == null) {
            return;
        }

        derivation.step(ROUNDS_PER_TICK);
        if (!derivation.isDone()) {
            WatchUi.requestUpdate();
            return;
        }

        stop();
        _derivation = null;

        // On success the app switches the view out from under this one, so
        // there is nothing left to draw. The digits are carried through to
        // here because a new PIN has no blob to try the key against: what
        // proves it right is that it was typed the same way twice.
        var typed = _entered;
        _entered = "";
        _first = null;

        if (_setting) {
            if (!getApp().onPinChosen(typed, derivation.key())) {
                fail(Rez.Strings.PinNotSaved);
            }
            return;
        }

        if (!getApp().onPinEntered(typed, derivation.key())) {
            fail(Rez.Strings.WrongPin);
        }
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        var derivation = _derivation;
        if (derivation != null) {
            drawProgress(dc, derivation.progress());
            return;
        }

        drawMessage(dc);
        drawDots(dc);
        drawKeypad(dc);
    }

    private function press(cell as Number) as Void {
        _notice = null;

        if (cell == CONFIRM) {
            confirm();
            WatchUi.requestUpdate();
            return;
        }

        if (cell == BACKSPACE) {
            if (_entered.length() > 0) {
                _entered = _entered.substring(0, _entered.length() - 1) as String;
            }
        } else if (_entered.length() < maxDigits()) {
            _entered += cell.toString();
        }

        // No confirm key when unlocking: the length is known before a digit is
        // typed, so the last one is the only signal needed.
        if (!_setting && _entered.length() == _pinLength) {
            begin();
        }
        WatchUi.requestUpdate();
    }

    // Typed twice, and compared before anything is derived — a PIN that seals
    // the only copy of a credential is not one to accept on a single attempt.
    private function confirm() as Void {
        if (!Sealed.isPin(_entered)) {
            _notice = WatchUi.loadResource(Rez.Strings.PinLength) as String;
            return;
        }

        var first = _first;
        if (first == null) {
            _first = _entered;
            _entered = "";
            return;
        }

        if (!first.equals(_entered)) {
            _first = null;
            _entered = "";
            _notice = WatchUi.loadResource(Rez.Strings.PinMismatch) as String;
            return;
        }

        begin();
    }

    private function fail(resource as ResourceId) as Void {
        _notice = WatchUi.loadResource(resource) as String;
        WatchUi.requestUpdate();
    }

    private function maxDigits() as Number {
        return _setting ? Sealed.MAX_PIN : _pinLength;
    }

    // How many dots to draw. A new PIN has no fixed length, so the row grows
    // past the minimum as digits are added.
    private function dotCount() as Number {
        if (!_setting) {
            return _pinLength;
        }
        return _entered.length() > Sealed.MIN_PIN ? _entered.length() : Sealed.MIN_PIN;
    }

    private function begin() as Void {
        _derivation = new KeyDerivation(_entered, _salt, _iterations);

        var timer = new Timer.Timer();
        timer.start(method(:onTick), TICK_MS, true);
        _timer = timer;
    }

    private function stop() as Void {
        var timer = _timer;
        if (timer != null) {
            timer.stop();
            _timer = null;
        }
    }

    // Null for a tap that missed every key — including the bottom-left cell,
    // which is only a key while a PIN is being chosen.
    private function cellAt(x as Number, y as Number) as Number? {
        var left = (_width * GRID_LEFT).toNumber();
        var right = (_width * GRID_RIGHT).toNumber();
        var top = (_height * GRID_TOP).toNumber();
        var bottom = (_height * GRID_BOTTOM).toNumber();

        if (x < left || x >= right || y < top || y >= bottom) {
            return null;
        }

        var column = ((x - left) * 3) / (right - left);
        var row = ((y - top) * 4) / (bottom - top);

        if (row < 3) {
            return row * 3 + column + 1;
        }
        if (column == 0) {
            return _setting ? CONFIRM : null;
        }
        return column == 1 ? 0 : BACKSPACE;
    }

    private function drawMessage(dc as Graphics.Dc) as Void {
        var notice = _notice;
        var text = notice;
        if (text == null) {
            if (!_setting) {
                return;
            }
            text = WatchUi.loadResource(
                _first == null ? Rez.Strings.PinChoose : Rez.Strings.PinRepeat) as String;
        }

        dc.setColor(notice != null ? Graphics.COLOR_RED : Graphics.COLOR_LT_GRAY,
            Graphics.COLOR_TRANSPARENT);
        dc.drawText(_width / 2, (_height * MESSAGE_Y).toNumber(), Graphics.FONT_XTINY, text,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    private function drawDots(dc as Graphics.Dc) as Void {
        var count = dotCount();
        var spacing = _width / 14;
        var radius = spacing / 4;
        var y = (_height * DOTS_Y).toNumber();
        var x = _width / 2 - ((count - 1) * spacing) / 2;

        for (var i = 0; i < count; i++) {
            if (i < _entered.length()) {
                dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(x + i * spacing, y, radius);
            } else {
                dc.setColor(_notice != null ? Graphics.COLOR_RED : Graphics.COLOR_DK_GRAY,
                    Graphics.COLOR_TRANSPARENT);
                dc.drawCircle(x + i * spacing, y, radius);
            }
        }
    }

    private function drawKeypad(dc as Graphics.Dc) as Void {
        var left = (_width * GRID_LEFT).toNumber();
        var top = (_height * GRID_TOP).toNumber();
        var cellWidth = ((_width * GRID_RIGHT).toNumber() - left) / 3;
        var cellHeight = ((_height * GRID_BOTTOM).toNumber() - top) / 4;

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);

        for (var i = 1; i <= 9; i++) {
            key(dc, left, top, cellWidth, cellHeight, (i - 1) % 3, (i - 1) / 3, i.toString());
        }
        key(dc, left, top, cellWidth, cellHeight, 1, 3, "0");

        drawBackspace(dc, left + 2 * cellWidth + cellWidth / 2,
            top + 3 * cellHeight + cellHeight / 2, cellWidth);

        if (_setting) {
            drawTick(dc, left + cellWidth / 2, top + 3 * cellHeight + cellHeight / 2, cellWidth);
        }
    }

    private function key(dc as Graphics.Dc, left as Number, top as Number, cellWidth as Number,
                         cellHeight as Number, column as Number, row as Number, label as String) as Void {
        dc.drawText(left + column * cellWidth + cellWidth / 2,
            top + row * cellHeight + cellHeight / 2,
            Graphics.FONT_MEDIUM, label,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // Drawn rather than written: no Garmin font carries a backspace glyph.
    private function drawBackspace(dc as Graphics.Dc, x as Number, y as Number, width as Number) as Void {
        var size = width / 6;
        dc.fillPolygon([
            [x - 2 * size, y],
            [x - size, y - size],
            [x - size, y + size]
        ] as Array<Graphics.Point2D>);
        dc.fillRectangle(x - size, y - size / 2, 2 * size, size);
    }

    // Two strokes rather than a checkmark glyph, for the same reason. The pen
    // width is put back: it is state on a context this view does not own.
    private function drawTick(dc as Graphics.Dc, x as Number, y as Number, width as Number) as Void {
        var size = width / 6;
        dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(4);
        dc.drawLine(x - size, y, x - size / 3, y + size);
        dc.drawLine(x - size / 3, y + size, x + size, y - size);
        dc.setPenWidth(1);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
    }

    private function drawProgress(dc as Graphics.Dc, fraction as Float) as Void {
        var centreX = _width / 2;
        var centreY = _height / 2;
        var radius = _width / 2 - 12;

        dc.setPenWidth(6);
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(centreX, centreY, radius);

        var sweep = (fraction * 359).toNumber();
        if (sweep > 0) {
            var end = 90 - sweep;
            if (end < 0) {
                end += 360;
            }
            dc.setColor(Graphics.COLOR_BLUE, Graphics.COLOR_TRANSPARENT);
            dc.drawArc(centreX, centreY, radius, Graphics.ARC_CLOCKWISE, 90, end);
        }

        dc.setPenWidth(1);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(centreX, centreY, Graphics.FONT_SMALL,
            WatchUi.loadResource(Rez.Strings.Checking) as String,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }
}
