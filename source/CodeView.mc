import Toybox.Cryptography;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.Timer;
import Toybox.WatchUi;

// Shows one account's current code, with a ring counting down the period.
class CodeView extends WatchUi.View {

    private const RING_WIDTH = 10;
    private const GAP = 6;
    private const MAX_TITLE_LINES = 3;
    private const TITLE_FONT = Graphics.FONT_XTINY;
    private const ACCENT = 0x0082C9;

    private var _issuer as String;
    private var _name as String;
    private var _period as Number;
    private var _digits as Number;
    private var _secret as ByteArray?;
    private var _algorithm as Cryptography.HashAlgorithm?;
    private var _error as String?;

    private var _timer as Timer.Timer?;
    private var _code as String = "";
    private var _remaining as Number = 0;

    function initialize(account as Dictionary, box as SecretBox?) {
        View.initialize();

        _issuer = account["issuer"] as String;
        _name = account["name"] as String;
        _period = account["period"] as Number;
        _digits = account["digits"] as Number;
        _error = prepare(account, box);
    }

    // Resolves the secret and algorithm up front. Returns the reason this
    // account cannot produce a code, or null when it can.
    private function prepare(account as Dictionary, box as SecretBox?) as String? {
        var type = account["type"] as String;
        if (!type.equals("totp")) {
            return WatchUi.loadResource(Rez.Strings.UnsupportedHotp) as String;
        }

        var algorithm = Totp.hashAlgorithm(account["algorithm"] as String);
        if (algorithm == null) {
            return WatchUi.loadResource(Rez.Strings.UnsupportedAlgorithm) as String;
        }
        _algorithm = algorithm;

        var secret = account["secret"] as String;
        if (box != null) {
            secret = box.decrypt(secret);
            if (secret == null) {
                return WatchUi.loadResource(Rez.Strings.DecryptFailed) as String;
            }
        }

        _secret = Base32.decode(secret);
        if (_secret == null || _secret.size() == 0) {
            return WatchUi.loadResource(Rez.Strings.DecryptFailed) as String;
        }

        return null;
    }

    function onShow() as Void {
        if (_error != null) {
            return;
        }
        tick();
        _timer = new Timer.Timer();
        _timer.start(method(:tick), 1000, true);
    }

    function onHide() as Void {
        if (_timer != null) {
            _timer.stop();
            _timer = null;
        }
    }

    function tick() as Void {
        var secret = _secret;
        var algorithm = _algorithm;
        if (secret == null || algorithm == null) {
            return;
        }

        var now = Time.now().value();
        _code = Totp.code(secret, Totp.counterFor(now, _period), _digits, algorithm);
        _remaining = Totp.secondsRemaining(now, _period);
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        if (dc has :setAntiAlias) {
            dc.setAntiAlias(true);
        }

        var centreX = dc.getWidth() / 2;
        var centreY = dc.getHeight() / 2;

        if (_error != null) {
            drawWrapped(dc, _error, Graphics.FONT_SMALL, centreX, centreY);
            return;
        }

        drawRing(dc, centreX, centreY);

        // The title can run to several lines, so the whole block is measured
        // first and then centred as one stack.
        var lines = titleLines(dc);
        var titleHeight = dc.getFontHeight(TITLE_FONT);
        var secondsHeight = titleHeight;

        var codeFont = fitFont(dc, grouped(_code), dc.getWidth() * 7 / 10);
        var codeHeight = dc.getFontHeight(codeFont);

        var total = lines.size() * titleHeight + GAP + codeHeight + GAP + secondsHeight;
        var y = centreY - total / 2;

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        for (var i = 0; i < lines.size(); i++) {
            dc.drawText(centreX, y, TITLE_FONT, lines[i], Graphics.TEXT_JUSTIFY_CENTER);
            y += titleHeight;
        }

        y += GAP;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(centreX, y, codeFont, grouped(_code), Graphics.TEXT_JUSTIFY_CENTER);
        y += codeHeight + GAP;

        dc.setColor(ACCENT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(centreX, y, Graphics.FONT_TINY, _remaining.toString() + "s",
            Graphics.TEXT_JUSTIFY_CENTER);
    }

    // Issuer and account name each get their own line (or lines), which reads
    // better than joining them and wrapping the join.
    private function titleLines(dc as Graphics.Dc) as Array<String> {
        var maxWidth = dc.getWidth() * 78 / 100;
        var lines = [] as Array<String>;

        if (!_issuer.equals("") && !_issuer.equals(_name)) {
            lines.addAll(Text.wrap(dc, _issuer, TITLE_FONT, maxWidth));
        }
        lines.addAll(Text.wrap(dc, _name, TITLE_FONT, maxWidth));

        // Beyond three lines the code itself starts to lose room.
        if (lines.size() <= MAX_TITLE_LINES) {
            return lines;
        }

        var kept = lines.slice(0, MAX_TITLE_LINES) as Array<String>;
        kept[MAX_TITLE_LINES - 1] = kept[MAX_TITLE_LINES - 1] + "…";
        return kept;
    }

    private function drawRing(dc as Graphics.Dc, centreX as Number, centreY as Number) as Void {
        var radius = centreX - RING_WIDTH;
        dc.setPenWidth(RING_WIDTH);

        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(centreX, centreY, radius);

        // Sweeps anticlockwise from 12 o'clock, shrinking as the period expires.
        var sweep = 360 * _remaining / _period;
        if (sweep > 0) {
            dc.setColor(_remaining <= 5 ? Graphics.COLOR_ORANGE : ACCENT, Graphics.COLOR_TRANSPARENT);
            dc.drawArc(centreX, centreY, radius, Graphics.ARC_CLOCKWISE, 90, 90 - sweep);
        }
    }

    // "123456" reads much better on a watch as "123 456".
    private function grouped(code as String) as String {
        if (code.length() != 6) {
            return code;
        }
        return code.substring(0, 3) + " " + code.substring(3, 6);
    }


    private function fitFont(dc as Graphics.Dc, text as String, maxWidth as Number) as Graphics.FontType {
        var fonts = [Graphics.FONT_NUMBER_THAI_HOT, Graphics.FONT_NUMBER_HOT,
                     Graphics.FONT_NUMBER_MEDIUM, Graphics.FONT_NUMBER_MILD,
                     Graphics.FONT_LARGE, Graphics.FONT_MEDIUM];

        for (var i = 0; i < fonts.size(); i++) {
            if (dc.getTextWidthInPixels(text, fonts[i]) <= maxWidth) {
                return fonts[i];
            }
        }
        return Graphics.FONT_SMALL;
    }


    private function drawWrapped(dc as Graphics.Dc, text as String, font as Graphics.FontType, centreX as Number, centreY as Number) as Void {
        var lines = Text.wrap(dc, text, font, dc.getWidth() * 3 / 4);
        var lineHeight = dc.getFontHeight(font);
        var y = centreY - (lines.size() * lineHeight) / 2;

        for (var i = 0; i < lines.size(); i++) {
            dc.drawText(centreX, y + i * lineHeight, font, lines[i], Graphics.TEXT_JUSTIFY_CENTER);
        }
    }
}
