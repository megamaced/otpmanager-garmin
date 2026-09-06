import Toybox.Cryptography;
import Toybox.Lang;
import Toybox.StringUtil;

// Mirrors the OTP Manager web client: the account secret is AES-256-CBC
// ciphertext, base64 encoded, keyed on SHA-256 of the user's OTP Manager
// password with a per-user IV the server hands back from /password/check.
class SecretBox {

    private var _key as ByteArray;
    private var _iv as ByteArray;

    function initialize(password as String, ivHex as String) {
        _key = Hmac.hash(Cryptography.HASH_SHA256, StringUtil.convertEncodedString(password, {
            :fromRepresentation => StringUtil.REPRESENTATION_STRING_PLAIN_TEXT,
            :toRepresentation => StringUtil.REPRESENTATION_BYTE_ARRAY
        }) as ByteArray);
        _iv = StringUtil.convertEncodedString(ivHex, {
            :fromRepresentation => StringUtil.REPRESENTATION_STRING_HEX,
            :toRepresentation => StringUtil.REPRESENTATION_BYTE_ARRAY
        }) as ByteArray;
    }

    // Returns null if the ciphertext is malformed or the password is wrong.
    function decrypt(cipherTextBase64 as String) as String? {
        var cipherText;
        try {
            cipherText = StringUtil.convertEncodedString(cipherTextBase64, {
                :fromRepresentation => StringUtil.REPRESENTATION_STRING_BASE64,
                :toRepresentation => StringUtil.REPRESENTATION_BYTE_ARRAY
            }) as ByteArray;
        } catch (e) {
            return null;
        }

        if (cipherText.size() == 0 || cipherText.size() % 16 != 0) {
            return null;
        }

        var plain;
        try {
            var cipher = new Cryptography.Cipher({
                :algorithm => Cryptography.CIPHER_AES256,
                :mode => Cryptography.MODE_CBC,
                :key => _key,
                :iv => _iv
            });
            plain = cipher.decrypt(cipherText);
        } catch (e) {
            return null;
        }

        return stripPkcs7(plain);
    }

    // Connect IQ ciphers do no padding of their own, so PKCS#7 comes off here.
    // A bad password shows up as an implausible pad length far more often than
    // not, which is the cheap integrity check this scheme allows.
    private function stripPkcs7(plain as ByteArray) as String? {
        var padLength = plain[plain.size() - 1];
        if (padLength < 1 || padLength > 16 || padLength > plain.size()) {
            return null;
        }

        for (var i = plain.size() - padLength; i < plain.size(); i++) {
            if (plain[i] != padLength) {
                return null;
            }
        }

        var body = plain.slice(0, plain.size() - padLength);
        return StringUtil.convertEncodedString(body, {
            :fromRepresentation => StringUtil.REPRESENTATION_BYTE_ARRAY,
            :toRepresentation => StringUtil.REPRESENTATION_STRING_PLAIN_TEXT
        }) as String;
    }
}
