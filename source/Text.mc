import Toybox.Graphics;
import Toybox.Lang;

module Text {

    // Greedy word wrap. Connect IQ has no multi-line text primitive that also
    // reports where it broke, and these strings have to fit a round screen.
    // Words with no spaces to break on — an email address, say — are split at
    // the character that no longer fits.
    function wrap(dc as Graphics.Dc, text as String, font as Graphics.FontType, maxWidth as Number) as Array<String> {
        var words = split(text, ' ');
        var lines = [] as Array<String>;
        var current = "";

        for (var i = 0; i < words.size(); i++) {
            var word = words[i];

            if (dc.getTextWidthInPixels(word, font) > maxWidth) {
                if (!current.equals("")) {
                    lines.add(current);
                    current = "";
                }
                var pieces = breakWord(dc, word, font, maxWidth);
                for (var j = 0; j < pieces.size() - 1; j++) {
                    lines.add(pieces[j]);
                }
                current = pieces[pieces.size() - 1];
                continue;
            }

            var candidate = current.equals("") ? word : current + " " + word;
            if (dc.getTextWidthInPixels(candidate, font) <= maxWidth) {
                current = candidate;
            } else {
                if (!current.equals("")) {
                    lines.add(current);
                }
                current = word;
            }
        }

        if (!current.equals("")) {
            lines.add(current);
        }

        return lines;
    }

    // Breaks a space-free word, preferring the punctuation an account name
    // tends to contain — "alice@example.co.uk" reads far better split after
    // the "@" than in the middle of "example".
    function breakWord(dc as Graphics.Dc, word as String, font as Graphics.FontType, maxWidth as Number) as Array<String> {
        var pieces = [] as Array<String>;
        var segments = segment(word);
        var current = "";

        for (var i = 0; i < segments.size(); i++) {
            var segment = segments[i];

            if (dc.getTextWidthInPixels(segment, font) > maxWidth) {
                if (!current.equals("")) {
                    pieces.add(current);
                    current = "";
                }
                var forced = breakChars(dc, segment, font, maxWidth);
                for (var j = 0; j < forced.size() - 1; j++) {
                    pieces.add(forced[j]);
                }
                current = forced[forced.size() - 1];
                continue;
            }

            var candidate = current + segment;
            if (current.equals("") || dc.getTextWidthInPixels(candidate, font) <= maxWidth) {
                current = candidate;
            } else {
                pieces.add(current);
                current = segment;
            }
        }

        pieces.add(current);
        return pieces;
    }

    // Splits after each separator, keeping it on the end of its segment.
    function segment(word as String) as Array<String> {
        var segments = [] as Array<String>;
        var chars = word.toCharArray();
        var current = "";

        for (var i = 0; i < chars.size(); i++) {
            var c = chars[i];
            current += c.toString();
            if (c == '@' || c == '.' || c == '-' || c == '_' || c == '/' || c == ':') {
                segments.add(current);
                current = "";
            }
        }

        if (!current.equals("")) {
            segments.add(current);
        }

        return segments;
    }

    function breakChars(dc as Graphics.Dc, word as String, font as Graphics.FontType, maxWidth as Number) as Array<String> {
        var pieces = [] as Array<String>;
        var chars = word.toCharArray();
        var current = "";

        for (var i = 0; i < chars.size(); i++) {
            var candidate = current + chars[i].toString();
            if (!current.equals("") && dc.getTextWidthInPixels(candidate, font) > maxWidth) {
                pieces.add(current);
                current = chars[i].toString();
            } else {
                current = candidate;
            }
        }

        pieces.add(current);
        return pieces;
    }

    function split(text as String, separator as Char) as Array<String> {
        var parts = [] as Array<String>;
        var chars = text.toCharArray();
        var current = "";

        for (var i = 0; i < chars.size(); i++) {
            if (chars[i] == separator) {
                if (!current.equals("")) {
                    parts.add(current);
                }
                current = "";
            } else {
                current += chars[i].toString();
            }
        }

        if (!current.equals("")) {
            parts.add(current);
        }

        return parts;
    }
}
