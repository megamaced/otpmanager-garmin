import Toybox.Cryptography;
import Toybox.Lang;
import Toybox.StringUtil;

// Encrypts account secrets that the server handed over in the clear, under the
// key the PIN derives, before they are written to Application.Storage.
//
// A vault with a password needs none of this: what the server sends is already
// ciphertext, and the password that opens it is inside the seal. A vault
// *without* one sends base32 TOTP seeds, and caching those verbatim meant a
// copy of watch storage yielded every seed without the PIN being involved —
// which is not what a PIN is advertised to do.
//
// The key is the PIN-derived one rather than a second secret, because there is
// nowhere on Connect IQ to keep a second secret that is any safer. That has a
// limit worth stating: while a grace-period unlock is live, that same key is in
// storage too, so this protects the cache only once the unlock has ended and
// the key has been erased. See the README on what the PIN is and is not worth.
module CacheBox {

    const BLOCK_SIZE = 16;

    function encrypt(plain as String, key as ByteArray, iv as ByteArray) as String? {
        var body = Sealed.pad(Sealed.utf8(plain));

        var cipherText;
        try {
            var cipher = new Cryptography.Cipher({
                :algorithm => Cryptography.CIPHER_AES256,
                :mode => Cryptography.MODE_CBC,
                :key => key,
                :iv => iv
            });
            cipherText = cipher.encrypt(body);
        } catch (e) {
            return null;
        }

        return StringUtil.convertEncodedString(cipherText, {
            :fromRepresentation => StringUtil.REPRESENTATION_BYTE_ARRAY,
            :toRepresentation => StringUtil.REPRESENTATION_STRING_BASE64
        }) as String;
    }

    function decrypt(encoded as String, key as ByteArray, iv as ByteArray) as String? {
        var cipherText;
        try {
            cipherText = StringUtil.convertEncodedString(encoded, {
                :fromRepresentation => StringUtil.REPRESENTATION_STRING_BASE64,
                :toRepresentation => StringUtil.REPRESENTATION_BYTE_ARRAY
            }) as ByteArray;
        } catch (e) {
            return null;
        }

        if (cipherText.size() == 0 || cipherText.size() % BLOCK_SIZE != 0) {
            return null;
        }

        var plain;
        try {
            var cipher = new Cryptography.Cipher({
                :algorithm => Cryptography.CIPHER_AES256,
                :mode => Cryptography.MODE_CBC,
                :key => key,
                :iv => iv
            });
            plain = cipher.decrypt(cipherText);
        } catch (e) {
            return null;
        }

        return unpad(plain);
    }

    function toHex(bytes as ByteArray) as String {
        return StringUtil.convertEncodedString(bytes, {
            :fromRepresentation => StringUtil.REPRESENTATION_BYTE_ARRAY,
            :toRepresentation => StringUtil.REPRESENTATION_STRING_HEX
        }) as String;
    }

    function fromHex(hex as String) as ByteArray? {
        try {
            return StringUtil.convertEncodedString(hex, {
                :fromRepresentation => StringUtil.REPRESENTATION_STRING_HEX,
                :toRepresentation => StringUtil.REPRESENTATION_BYTE_ARRAY
            }) as ByteArray;
        } catch (e) {
            return null;
        }
    }

    function unpad(plain as ByteArray) as String? {
        var padLength = plain[plain.size() - 1];
        if (padLength < 1 || padLength > BLOCK_SIZE || padLength >= plain.size()) {
            return null;
        }

        for (var i = plain.size() - padLength; i < plain.size(); i++) {
            if (plain[i] != padLength) {
                return null;
            }
        }

        return StringUtil.convertEncodedString(plain.slice(0, plain.size() - padLength), {
            :fromRepresentation => StringUtil.REPRESENTATION_BYTE_ARRAY,
            :toRepresentation => StringUtil.REPRESENTATION_STRING_PLAIN_TEXT
        }) as String;
    }
}
