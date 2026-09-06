import Toybox.Cryptography;
import Toybox.Lang;
import Toybox.Test;

// RFC 6238 appendix B vectors, plus a ciphertext produced the way the OTP
// Manager server produces one. Excluded from release builds by (:test).

const RFC_SECRET_SHA1 = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ";
const RFC_SECRET_SHA256 = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZA====";
const AES_CIPHERTEXT = "JC04zC5hUeIFnLfUOFHBjOsqs4L2vuAdx996EW9TqaNa+PKxxw/NwBt/sF75cNTH";
const AES_IV = "0f1e2d3c4b5a69788796a5b4c3d2e1f0";

(:test)
function testBase32DecodesAscii(logger as Logger) as Boolean {
    var decoded = decodeOrFail("GEZDGNBVGY3TQOJQ");
    var expected = [0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x30]b;

    Test.assertEqual(decoded.size(), expected.size());
    for (var i = 0; i < expected.size(); i++) {
        Test.assertEqual(decoded[i], expected[i]);
    }
    return true;
}

(:test)
function testBase32IgnoresPaddingAndCase(logger as Logger) as Boolean {
    Test.assertEqual(decodeOrFail("gezdgnbv").toString(), decodeOrFail("GEZDGNBV====").toString());
    return true;
}

(:test)
function testBase32RejectsInvalidCharacters(logger as Logger) as Boolean {
    Test.assertMessage(Base32.decode("GEZD1NBV") == null, "'1' is not in the base32 alphabet");
    return true;
}

(:test)
function testTotpSha1MatchesRfc6238(logger as Logger) as Boolean {
    assertTotp(RFC_SECRET_SHA1, 59, 8, Cryptography.HASH_SHA1, "94287082");
    assertTotp(RFC_SECRET_SHA1, 1111111109, 8, Cryptography.HASH_SHA1, "07081804");
    assertTotp(RFC_SECRET_SHA1, 1111111111, 8, Cryptography.HASH_SHA1, "14050471");
    assertTotp(RFC_SECRET_SHA1, 1234567890, 8, Cryptography.HASH_SHA1, "89005924");
    assertTotp(RFC_SECRET_SHA1, 2000000000, 8, Cryptography.HASH_SHA1, "69279037");
    return true;
}

(:test)
function testTotpSha256MatchesRfc6238(logger as Logger) as Boolean {
    assertTotp(RFC_SECRET_SHA256, 59, 8, Cryptography.HASH_SHA256, "46119246");
    assertTotp(RFC_SECRET_SHA256, 1111111109, 8, Cryptography.HASH_SHA256, "68084774");
    assertTotp(RFC_SECRET_SHA256, 1234567890, 8, Cryptography.HASH_SHA256, "91819424");
    assertTotp(RFC_SECRET_SHA256, 2000000000, 8, Cryptography.HASH_SHA256, "90698825");
    return true;
}

// Six digits is what real accounts use, and it exercises the zero padding.
(:test)
function testTotpSixDigitsAreZeroPadded(logger as Logger) as Boolean {
    assertTotp(RFC_SECRET_SHA1, 1234567890, 6, Cryptography.HASH_SHA1, "005924");
    return true;
}

(:test)
function testPeriodCountdown(logger as Logger) as Boolean {
    Test.assertEqual(Totp.counterFor(59, 30), 1);
    Test.assertEqual(Totp.counterFor(60, 30), 2);
    Test.assertEqual(Totp.secondsRemaining(59, 30), 1);
    Test.assertEqual(Totp.secondsRemaining(60, 30), 30);
    return true;
}

(:test)
function testAlgorithmMapping(logger as Logger) as Boolean {
    Test.assertMessage(Totp.hashAlgorithm("SHA512") == null, "SHA512 has no Connect IQ equivalent");
    Test.assertMessage(Totp.hashAlgorithm("sha1") == Cryptography.HASH_SHA1, "SHA1 should map, case-insensitively");
    Test.assertMessage(Totp.hashAlgorithm("SHA256") == Cryptography.HASH_SHA256, "SHA256 should map");
    return true;
}

(:test)
function testSecretBoxDecryptsServerCiphertext(logger as Logger) as Boolean {
    var box = new SecretBox("hunter2", AES_IV);
    var plain = box.decrypt(AES_CIPHERTEXT);

    Test.assertMessage(plain != null, "decryption returned null");
    Test.assertEqual(plain as String, RFC_SECRET_SHA1);
    return true;
}

(:test)
function testSecretBoxRejectsWrongPassword(logger as Logger) as Boolean {
    var box = new SecretBox("wrong", AES_IV);
    Test.assertMessage(box.decrypt(AES_CIPHERTEXT) == null, "a wrong password should not yield a secret");
    return true;
}

(:test)
function testSecretBoxRejectsMalformedCiphertext(logger as Logger) as Boolean {
    var box = new SecretBox("hunter2", AES_IV);
    Test.assertMessage(box.decrypt("AAAA") == null, "a non-block-sized ciphertext should be rejected");
    return true;
}

function decodeOrFail(encoded as String) as ByteArray {
    var decoded = Base32.decode(encoded);
    Test.assertMessage(decoded != null, "base32 decode failed for " + encoded);
    return decoded as ByteArray;
}

function assertTotp(secret as String, time as Number, digits as Number, algorithm as Cryptography.HashAlgorithm, expected as String) as Void {
    var actual = Totp.code(decodeOrFail(secret), Totp.counterFor(time, 30), digits, algorithm);
    Test.assertMessage(actual.equals(expected),
        "t=" + time.toString() + " expected " + expected + " got " + actual);
}
