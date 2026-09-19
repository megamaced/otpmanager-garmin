import Toybox.Cryptography;
import Toybox.Lang;
import Toybox.StringUtil;

// Everything the app needs to reach the vault, as one AES-256-CBC blob keyed
// on the wearer's PIN, so that neither the .prg nor any store holds a password
// in the clear. tools/seal.py produces the identical format at build time for
// sideloads.
//
//   version:1  pinLength:1  iterations:4 (big endian)  salt:16  iv:16  ct:16n
//
// and inside the ciphertext, PKCS#7 padded to the block size:
//
//   "OTPM"  length:1 username  length:1 appPassword  length:1 otpPassword
//
// The magic is what rejects a wrong PIN. The upstream vault format has no such
// marker and has to infer a bad password from implausible padding; this format
// is ours to define, so it can simply say no.
module Sealed {

    // Version 1 carried only the two passwords, from back when the username
    // was typed into the settings screen rather than returned by a sign-in.
    // Such a blob is rejected rather than migrated: it cannot say who it
    // belongs to, and signing in again is two taps.
    const VERSION = 2;
    const HEADER_SIZE = 38;
    const SALT_SIZE = 16;
    const IV_SIZE = 16;
    const BLOCK_SIZE = 16;
    const MIN_PIN = 4;
    const MAX_PIN = 8;

    // What one PIN guess costs. Written into the blob rather than assumed, so
    // raising it later does not strand a seal made under the old count.
    const ITERATIONS = 5000;

    function parse(encoded as String) as SealedBlob? {
        var blob;
        try {
            blob = StringUtil.convertEncodedString(encoded, {
                :fromRepresentation => StringUtil.REPRESENTATION_STRING_BASE64,
                :toRepresentation => StringUtil.REPRESENTATION_BYTE_ARRAY
            }) as ByteArray;
        } catch (e) {
            return null;
        }

        if (blob.size() < HEADER_SIZE + BLOCK_SIZE || blob[0] != VERSION) {
            return null;
        }

        var pinLength = blob[1];
        if (pinLength < MIN_PIN || pinLength > MAX_PIN) {
            return null;
        }

        var iterations = (blob[2] << 24) | (blob[3] << 16) | (blob[4] << 8) | blob[5];
        if (iterations < 1) {
            return null;
        }

        var cipherText = blob.slice(HEADER_SIZE, blob.size());
        if (cipherText.size() % BLOCK_SIZE != 0) {
            return null;
        }

        return new SealedBlob(pinLength, iterations,
            blob.slice(6, 6 + SALT_SIZE),
            blob.slice(6 + SALT_SIZE, HEADER_SIZE),
            cipherText);
    }

    // Used whenever the PIN was chosen on the watch rather than compiled in.
    // The key is passed in rather than derived here: deriving it takes about as
    // long as everything else this app does put together, and it belongs on the
    // PIN screen's timer where it cannot block long enough to be killed.
    //
    // The salt must be the one the key was derived from, and the caller owns
    // both — they are fresh per seal, so the same credentials under the same
    // PIN produce a different blob each time.
    function sealWithKey(credentials as Credentials, pinLength as Number,
                         salt as ByteArray, iv as ByteArray, key as ByteArray) as String? {
        var user = utf8(credentials.username);
        var app = utf8(credentials.appPassword);
        var otp = utf8(credentials.otpPassword);
        if (user.size() > 255 || app.size() > 255 || otp.size() > 255) {
            return null;
        }

        var body = magic()
            .add(user.size()).addAll(user)
            .add(app.size()).addAll(app)
            .add(otp.size()).addAll(otp);

        var cipher = new Cryptography.Cipher({
            :algorithm => Cryptography.CIPHER_AES256,
            :mode => Cryptography.MODE_CBC,
            :key => key,
            :iv => iv
        });

        var blob = [VERSION, pinLength]b
            .addAll(bigEndian(ITERATIONS))
            .addAll(salt)
            .addAll(iv)
            .addAll(cipher.encrypt(pad(body)));

        return StringUtil.convertEncodedString(blob, {
            :fromRepresentation => StringUtil.REPRESENTATION_BYTE_ARRAY,
            :toRepresentation => StringUtil.REPRESENTATION_STRING_BASE64
        }) as String;
    }

    function salt() as ByteArray {
        return Cryptography.randomBytes(SALT_SIZE);
    }

    function iv() as ByteArray {
        return Cryptography.randomBytes(IV_SIZE);
    }

    // Digits only, and of a length the keypad can ask for.
    function isPin(pin as String) as Boolean {
        if (pin.length() < MIN_PIN || pin.length() > MAX_PIN) {
            return false;
        }

        var chars = pin.toCharArray();
        for (var i = 0; i < chars.size(); i++) {
            if (chars[i] < '0' || chars[i] > '9') {
                return false;
            }
        }
        return true;
    }

    function utf8(text as String) as ByteArray {
        return StringUtil.convertEncodedString(text, {
            :fromRepresentation => StringUtil.REPRESENTATION_STRING_PLAIN_TEXT,
            :toRepresentation => StringUtil.REPRESENTATION_BYTE_ARRAY
        }) as ByteArray;
    }

    function magic() as ByteArray {
        return [0x4F, 0x54, 0x50, 0x4D]b;
    }

    function bigEndian(value as Number) as ByteArray {
        return [(value >> 24) & 0xff, (value >> 16) & 0xff,
                (value >> 8) & 0xff, value & 0xff]b;
    }

    // Connect IQ ciphers do no padding of their own, in either direction.
    function pad(body as ByteArray) as ByteArray {
        var padLength = BLOCK_SIZE - (body.size() % BLOCK_SIZE);
        var padded = body;
        for (var i = 0; i < padLength; i++) {
            padded = padded.add(padLength);
        }
        return padded;
    }
}

// One parsed blob. The header is readable without the PIN — the key derivation
// needs the salt, and the keypad needs to know how many digits to collect.
class SealedBlob {

    var pinLength as Number;
    var iterations as Number;
    var salt as ByteArray;

    private var _iv as ByteArray;
    private var _cipherText as ByteArray;

    function initialize(pinLength as Number, iterations as Number, salt as ByteArray,
                        iv as ByteArray, cipherText as ByteArray) {
        self.pinLength = pinLength;
        self.iterations = iterations;
        self.salt = salt;
        _iv = iv;
        _cipherText = cipherText;
    }

    // Null whenever the key does not open the blob, which in practice means the
    // wearer typed the wrong PIN.
    function open(key as ByteArray) as Credentials? {
        var plain;
        try {
            var cipher = new Cryptography.Cipher({
                :algorithm => Cryptography.CIPHER_AES256,
                :mode => Cryptography.MODE_CBC,
                :key => key,
                :iv => _iv
            });
            plain = cipher.decrypt(_cipherText);
        } catch (e) {
            return null;
        }

        var body = unpad(plain);
        if (body == null) {
            return null;
        }
        return unpack(body as ByteArray);
    }

    private function unpad(plain as ByteArray) as ByteArray? {
        var padLength = plain[plain.size() - 1];
        if (padLength < 1 || padLength > Sealed.BLOCK_SIZE || padLength >= plain.size()) {
            return null;
        }

        for (var i = plain.size() - padLength; i < plain.size(); i++) {
            if (plain[i] != padLength) {
                return null;
            }
        }
        return plain.slice(0, plain.size() - padLength);
    }

    // Every length is checked against what is actually there: a wrong key that
    // happened to pad plausibly must not be able to index past the end.
    private function unpack(body as ByteArray) as Credentials? {
        var magic = Sealed.magic();
        if (body.size() < magic.size() + 3) {
            return null;
        }
        for (var i = 0; i < magic.size(); i++) {
            if (body[i] != magic[i]) {
                return null;
            }
        }

        var at = magic.size();
        var userLength = body[at];
        at++;
        if (at + userLength + 2 > body.size()) {
            return null;
        }
        var user = body.slice(at, at + userLength);

        at += userLength;
        var appLength = body[at];
        at++;
        if (at + appLength + 1 > body.size()) {
            return null;
        }
        var app = body.slice(at, at + appLength);

        at += appLength;
        var otpLength = body[at];
        at++;
        if (at + otpLength != body.size()) {
            return null;
        }
        var otp = body.slice(at, at + otpLength);

        return new Credentials(text(user), text(app), text(otp));
    }

    private function text(bytes as ByteArray) as String {
        return StringUtil.convertEncodedString(bytes, {
            :fromRepresentation => StringUtil.REPRESENTATION_BYTE_ARRAY,
            :toRepresentation => StringUtil.REPRESENTATION_STRING_PLAIN_TEXT
        }) as String;
    }
}

// The three things the app cannot work without, and the unit a seal is made of.
class Credentials {

    var username as String;
    var appPassword as String;
    var otpPassword as String;

    function initialize(username as String, appPassword as String, otpPassword as String) {
        self.username = username;
        self.appPassword = appPassword;
        self.otpPassword = otpPassword;
    }

    function isComplete() as Boolean {
        return !username.equals("") && !appPassword.equals("") && !otpPassword.equals("");
    }
}

// Iterated SHA-256, run a few hundred rounds at a time so the watchdog never
// sees a long block of computation. There is no PBKDF2 in Connect IQ and
// nothing memory-hard, so the iteration count is the only defence a four to
// eight digit PIN has — and against a GPU, not much of one. See the security
// section of the README for what this does and does not buy.
//
//   state = SHA256(salt + pin), then SHA256(state + salt) iterations-1 times
class KeyDerivation {

    private var _hash as Cryptography.Hash;
    private var _salt as ByteArray;
    private var _state as ByteArray;
    private var _total as Number;
    private var _done as Number;

    function initialize(pin as String, salt as ByteArray, iterations as Number) {
        _hash = new Cryptography.Hash({ :algorithm => Cryptography.HASH_SHA256 });
        _salt = salt;
        _total = iterations;
        _done = 1;

        // Built from an empty array rather than by appending to the caller's
        // salt: whether ByteArray.addAll copies or extends in place is not
        // worth depending on, and a mutated salt would break the next attempt.
        var seed = []b;
        seed = seed.addAll(salt);
        seed = seed.addAll(Sealed.utf8(pin));
        _state = digest(seed);
    }

    function isDone() as Boolean {
        return _done >= _total;
    }

    // 0.0 to 1.0, for the progress ring on the PIN screen.
    function progress() as Float {
        return _done.toFloat() / _total.toFloat();
    }

    function step(rounds as Number) as Void {
        var end = _done + rounds;
        if (end > _total) {
            end = _total;
        }
        while (_done < end) {
            _state = digest(_state.addAll(_salt));
            _done++;
        }
    }

    function key() as ByteArray {
        return _state;
    }

    // digest() resets the object, so one Hash serves every round.
    private function digest(data as ByteArray) as ByteArray {
        _hash.update(data);
        return _hash.digest();
    }
}
