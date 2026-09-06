import Toybox.Cryptography;
import Toybox.Lang;

// HMAC built on Cryptography.Hash rather than on
// Cryptography.HashBasedMessageAuthenticationCode, whose SHA-1 support is
// documented only for SHA-256. Hash itself offers both on every target device.
module Hmac {

    const BLOCK_SIZE = 64;

    function digest(algorithm as Cryptography.HashAlgorithm, key as ByteArray, message as ByteArray) as ByteArray {
        var shortened = key.size() > BLOCK_SIZE ? hash(algorithm, key) : key;

        var inner = new [64]b;
        var outer = new [64]b;
        for (var i = 0; i < BLOCK_SIZE; i++) {
            var b = i < shortened.size() ? shortened[i] : 0x00;
            inner[i] = b ^ 0x36;
            outer[i] = b ^ 0x5c;
        }

        var innerDigest = hash(algorithm, inner.addAll(message));
        return hash(algorithm, outer.addAll(innerDigest));
    }

    function hash(algorithm as Cryptography.HashAlgorithm, data as ByteArray) as ByteArray {
        var h = new Cryptography.Hash({ :algorithm => algorithm });
        h.update(data);
        return h.digest();
    }
}
