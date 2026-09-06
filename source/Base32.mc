import Toybox.Lang;

// RFC 4648 base32, decode only. OTP secrets are stored base32 encoded.
module Base32 {

    // Returns null when the input contains a character outside the alphabet.
    function decode(encoded as String) as ByteArray? {
        var chars = encoded.toUpper().toCharArray();
        var out = []b;
        var buffer = 0;
        var bits = 0;

        for (var i = 0; i < chars.size(); i++) {
            var c = chars[i];
            if (c == '=' || c == ' ' || c == '-') {
                continue;
            }

            var value;
            if (c >= 'A' && c <= 'Z') {
                value = c.toNumber() - 'A'.toNumber();
            } else if (c >= '2' && c <= '7') {
                value = c.toNumber() - '2'.toNumber() + 26;
            } else {
                return null;
            }

            buffer = (buffer << 5) | value;
            bits += 5;

            if (bits >= 8) {
                bits -= 8;
                out.add((buffer >> bits) & 0xff);
            }
        }

        return out;
    }
}
