import Toybox.Cryptography;
import Toybox.Lang;
import Toybox.Math;

module Totp {

    // Maps an OTP Manager algorithm name onto a Cryptography.HashAlgorithm.
    // SHA512 has no equivalent on Connect IQ, so it returns null.
    function hashAlgorithm(name as String) as Cryptography.HashAlgorithm? {
        var upper = name.toUpper();
        if (upper.equals("SHA1")) {
            return Cryptography.HASH_SHA1;
        } else if (upper.equals("SHA256")) {
            return Cryptography.HASH_SHA256;
        }
        return null;
    }

    // RFC 4226 HOTP: the shared primitive behind both HOTP and TOTP.
    function code(secret as ByteArray, counter as Number, digits as Number, algorithm as Cryptography.HashAlgorithm) as String {
        var message = new [8]b;
        var remaining = counter;
        for (var i = 7; i >= 0; i--) {
            message[i] = remaining & 0xff;
            remaining = remaining >> 8;
        }

        var mac = Hmac.digest(algorithm, secret, message);

        var offset = mac[mac.size() - 1] & 0x0f;
        var truncated = ((mac[offset] & 0x7f) << 24)
            | ((mac[offset + 1] & 0xff) << 16)
            | ((mac[offset + 2] & 0xff) << 8)
            | (mac[offset + 3] & 0xff);

        var modulus = 1;
        for (var i = 0; i < digits; i++) {
            modulus *= 10;
        }

        return pad(truncated % modulus, digits);
    }

    function counterFor(unixTime as Number, period as Number) as Number {
        return unixTime / period;
    }

    function secondsRemaining(unixTime as Number, period as Number) as Number {
        return period - (unixTime % period);
    }

    function pad(value as Number, digits as Number) as String {
        var s = value.toString();
        while (s.length() < digits) {
            s = "0" + s;
        }
        return s;
    }
}
