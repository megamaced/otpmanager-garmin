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
//   iv:16  ciphertext:16n  tag:32        base64, one blob per secret
//
// Encrypt-then-MAC, with the account's label mixed into the tag, so a cache
// that has been edited, or whose blobs have been swapped between accounts, is
// rejected rather than turned into a plausible wrong code. The IV is per
// secret rather than per cache: one IV across a list would make two identical
// seeds encrypt identically.
//
// The key is the PIN-derived one rather than a second secret, because there is
// nowhere on Connect IQ to keep a second secret that is any safer. That has a
// limit worth stating: while a grace-period unlock is live, that same key is in
// storage too, so this protects the cache only once the unlock has ended and
// the key has been erased. See the README on what the PIN is and is not worth.
module CacheBox {

    const BLOCK_SIZE = 16;
    const IV_SIZE = 16;
    const TAG_SIZE = 32;

    function seal(plain as String, label as String, key as ByteArray) as String? {
        var iv = Cryptography.randomBytes(IV_SIZE);

        var cipherText;
        try {
            var cipher = new Cryptography.Cipher({
                :algorithm => Cryptography.CIPHER_AES256,
                :mode => Cryptography.MODE_CBC,
                :key => key,
                :iv => iv
            });
            cipherText = cipher.encrypt(Sealed.pad(Sealed.utf8(plain)));
        } catch (e) {
            return null;
        }

        // Built up from empty arrays rather than by appending to iv: whether
        // ByteArray.addAll copies or extends in place is not worth depending
        // on, and the tag has to be taken over bytes nothing else will touch.
        var authenticated = []b;
        authenticated = authenticated.addAll(iv);
        authenticated = authenticated.addAll(cipherText);

        var blob = []b;
        blob = blob.addAll(authenticated);
        blob = blob.addAll(tag(key, label, authenticated));

        return StringUtil.convertEncodedString(blob, {
            :fromRepresentation => StringUtil.REPRESENTATION_BYTE_ARRAY,
            :toRepresentation => StringUtil.REPRESENTATION_STRING_BASE64
        }) as String;
    }

    function open(encoded as String, label as String, key as ByteArray) as String? {
        var decoded = decode(encoded);
        if (decoded == null) {
            return null;
        }

        var blob = decoded as ByteArray;
        var bodySize = blob.size() - TAG_SIZE;
        if (bodySize < IV_SIZE + BLOCK_SIZE || (bodySize - IV_SIZE) % BLOCK_SIZE != 0) {
            return null;
        }

        // Checked before anything is decrypted. Padding that is examined first
        // answers questions about ciphertexts this app never wrote, and a
        // secret restored from an edited cache is a wrong code rather than a
        // missing one.
        var authenticated = blob.slice(0, bodySize);
        if (!sameBytes(blob.slice(bodySize, blob.size()), tag(key, label, authenticated))) {
            return null;
        }

        var plain;
        try {
            var cipher = new Cryptography.Cipher({
                :algorithm => Cryptography.CIPHER_AES256,
                :mode => Cryptography.MODE_CBC,
                :key => key,
                :iv => authenticated.slice(0, IV_SIZE)
            });
            plain = cipher.decrypt(authenticated.slice(IV_SIZE, bodySize));
        } catch (e) {
            return null;
        }

        return unpad(plain);
    }

    // The label is what stops a blob being lifted from one account and read as
    // another's seed: the tag only verifies where the secret was written.
    function tag(key as ByteArray, label as String, body as ByteArray) as ByteArray {
        var hmac = new Cryptography.HashBasedMessageAuthenticationCode({
            :algorithm => Cryptography.HASH_SHA256,
            :key => macKey(key)
        });
        hmac.update(body);
        hmac.update(Sealed.utf8(label));
        return hmac.digest();
    }

    // Derived rather than reused, so the bytes that encrypt and the bytes that
    // authenticate are never the same ones.
    function macKey(key as ByteArray) as ByteArray {
        var hash = new Cryptography.Hash({ :algorithm => Cryptography.HASH_SHA256 });
        hash.update(key);
        hash.update(Sealed.utf8("otpmanager-cache-mac"));
        return hash.digest();
    }

    // Every byte, every time: a comparison that stops at the first difference
    // tells whoever is feeding it ciphertexts how much of the tag they have.
    function sameBytes(a as ByteArray, b as ByteArray) as Boolean {
        if (a.size() != b.size()) {
            return false;
        }

        var diff = 0;
        for (var i = 0; i < a.size(); i++) {
            diff |= a[i] ^ b[i];
        }
        return diff == 0;
    }

    function decode(encoded as String) as ByteArray? {
        try {
            return StringUtil.convertEncodedString(encoded, {
                :fromRepresentation => StringUtil.REPRESENTATION_STRING_BASE64,
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
