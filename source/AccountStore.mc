import Toybox.Application;
import Toybox.Lang;

// Caches the last successful fetch so the app opens straight into the account
// list, and still works when the phone is out of range. A vault with a password
// sends ciphertext, which is cached as it arrived; a vault without one sends
// seeds, which are encrypted under the PIN key first — see CacheBox.
//
// Whenever there is a PIN key, the **whole record** is authenticated: every
// account, the server's IV, the fingerprint, and the two flags that say how the
// secrets are held. Authenticating only the secrets left those flags free to
// say "nothing was encrypted here, so check nothing" — and a record that
// decides for itself whether it is checked is not checked at all. For the same
// reason the check is made whenever this app holds a key, rather than whenever
// the record claims to want one.
class AccountStore {

    private static const STORAGE_KEY = "vault";

    // Signing out drops the cache with everything else. The secrets in it are
    // still encrypted, but they belong to an account the watch no longer has
    // credentials for.
    static function clearCache() as Void {
        Application.Storage.deleteValue(STORAGE_KEY);
    }

    private var _config as Config;
    private var _accounts as Array<Dictionary> = [] as Array<Dictionary>;
    private var _iv as String = "";
    private var _encrypted as Boolean = false;
    private var _loaded as Boolean = false;

    function initialize(config as Config) {
        _config = config;

        // While the credentials are still sealed the fingerprint cannot match,
        // and restoring would throw away a cache that is about to be valid.
        if (config.isComplete()) {
            restore();
            return;
        }

        // Sealed, so the cache cannot be read here — but whether it was written
        // while a PIN existed can be seen without any key, and a PIN that only
        // takes effect at the next unlock leaves open exactly what it was set
        // to close.
        if (config.isSealed()) {
            discardIfPlaintext();
        }
    }

    // Loaded and empty is a real, cacheable state: a vault with no accounts in
    // it. Conflating it with "no cache" would re-fetch on every launch.
    function isLoaded() as Boolean {
        return _loaded;
    }

    function isEmpty() as Boolean {
        return _accounts.size() == 0;
    }

    function getAccounts() as Array<Dictionary> {
        return _accounts;
    }

    function secretBox() as SecretBox? {
        if (!_encrypted) {
            return null;
        }
        return new SecretBox(_config.otpPassword, _iv);
    }

    function update(payload as Dictionary) as Void {
        _accounts = payload["accounts"] as Array<Dictionary>;
        _iv = payload["iv"] as String;
        _encrypted = payload["encrypted"] as Boolean;
        _loaded = true;
        persist();
    }

    // Writes what is in memory. Split out so that setting a PIN can re-write an
    // existing cache under the new key rather than throwing it away and making
    // the wearer find a phone.
    function persist() as Void {
        if (!_loaded) {
            return;
        }

        var key = _config.localKey();
        var fingerprint = _config.fingerprint();
        var accounts = _accounts;
        var localSealed = false;

        // Only a passwordless vault needs its secrets encrypted here. Anything
        // else is already ciphertext whose key lives inside the seal.
        if (!_encrypted && key != null) {
            var sealedAccounts = withSecrets(_accounts, key as ByteArray, true);
            if (sealedAccounts == null) {
                // Falling back to writing the seeds in the clear would undo
                // the PIN silently. Dropping the cache costs a refresh the
                // next time the app opens, and nothing else.
                Application.Storage.deleteValue(STORAGE_KEY);
                return;
            }
            accounts = sealedAccounts as Array<Dictionary>;
            localSealed = true;
        }

        // No key means no PIN, and nothing to authenticate with. The cache is
        // then exactly as exposed as the credentials are, which is the trade
        // the wearer made by not setting one.
        var tag = "";
        if (key != null) {
            var canonical = canonicalEnvelope(fingerprint, _iv, _encrypted, localSealed, accounts);
            if (canonical == null) {
                Application.Storage.deleteValue(STORAGE_KEY);
                return;
            }
            tag = CacheBox.toBase64(CacheBox.tag(key as ByteArray, canonical as String));
        }

        var record = {
            "fingerprint" => fingerprint,
            "accounts" => accounts,
            "iv" => _iv,
            "encrypted" => _encrypted,
            "localSealed" => localSealed,
            "tag" => tag
        };
        Application.Storage.setValue(STORAGE_KEY, record as Application.Storage.ValueType);
    }

    private function restore() as Void {
        var cached = Application.Storage.getValue(STORAGE_KEY);
        if (!(cached instanceof Dictionary)) {
            return;
        }

        // A record from the build that kept one IV per cache rather than one
        // per secret. Its secrets are ciphertext that this code would read as
        // seeds, so it is dropped rather than misread.
        if (cached.hasKey("localIv")) {
            Application.Storage.deleteValue(STORAGE_KEY);
            return;
        }

        // A changed server, user or vault password makes the cache undecryptable.
        var fingerprint = cached["fingerprint"];
        if (!(fingerprint instanceof Number) || fingerprint != _config.fingerprint()) {
            Application.Storage.deleteValue(STORAGE_KEY);
            return;
        }

        var accounts = cached["accounts"];
        var iv = cached["iv"];
        var encrypted = cached["encrypted"];
        if (!(accounts instanceof Array) || !(iv instanceof String) || !(encrypted instanceof Boolean)) {
            Application.Storage.deleteValue(STORAGE_KEY);
            return;
        }

        var records = accounts as Array<Dictionary>;
        var localSealed = isSealedLocally(cached);

        // Null unless every account is exactly the shape this app writes, which
        // is the other half of what the tag is worth: the menu and the code
        // screen read these fields without checking them, so a record that has
        // lost one is a crash rather than a missing account.
        var canonical = canonicalEnvelope(fingerprint, iv, encrypted, localSealed, records);
        if (canonical == null) {
            Application.Storage.deleteValue(STORAGE_KEY);
            return;
        }

        var key = _config.localKey();
        if (key != null) {
            if (!isAuthentic(cached, key as ByteArray, canonical as String)) {
                Application.Storage.deleteValue(STORAGE_KEY);
                return;
            }
        } else if (localSealed) {
            // Encrypted here, and nothing to open it with.
            Application.Storage.deleteValue(STORAGE_KEY);
            return;
        }

        if (localSealed) {
            var opened = withSecrets(records, key as ByteArray, false);
            if (opened == null) {
                Application.Storage.deleteValue(STORAGE_KEY);
                return;
            }
            records = opened as Array<Dictionary>;
        }

        _accounts = records;
        _iv = iv;
        _encrypted = encrypted;
        _loaded = true;
    }

    // Deletes a cached record written before a PIN existed, whose secrets are
    // therefore held as the server sent them — for a passwordless vault, in the
    // clear. Nothing here can be verified, because the key is exactly what is
    // missing while the app is locked; presence of a tag is enough, because a
    // forged one only preserves a cache its forger could already read, and the
    // next unlock checks it properly.
    private function discardIfPlaintext() as Void {
        var cached = Application.Storage.getValue(STORAGE_KEY);
        if (!(cached instanceof Dictionary)) {
            return;
        }

        var tag = cached["tag"];
        if (tag instanceof String && !tag.equals("")) {
            return;
        }

        Application.Storage.deleteValue(STORAGE_KEY);
    }

    // The stored record's own type, spelled out: a value that came back from
    // Application.Storage will not pass as a bare Dictionary.
    private function isAuthentic(
            cached as Dictionary<Application.Storage.KeyType, Application.Storage.ValueType>,
            key as ByteArray, canonical as String) as Boolean {
        var tag = cached["tag"];
        if (!(tag instanceof String)) {
            return false;
        }

        var presented = CacheBox.decode(tag);
        if (presented == null) {
            return false;
        }
        return CacheBox.sameBytes(presented as ByteArray, CacheBox.tag(key, canonical));
    }

    private function isSealedLocally(
            cached as Dictionary<Application.Storage.KeyType, Application.Storage.ValueType>) as Boolean {
        var marker = cached["localSealed"];
        if (marker instanceof Boolean) {
            return marker;
        }
        return false;
    }

    // The same account list with every secret run through CacheBox one way or
    // the other. Null if any of them fails, because a cache that is half
    // readable is worse than none: the failure would surface later as a wrong
    // code rather than as a missing one.
    private function withSecrets(accounts as Array<Dictionary>, key as ByteArray,
                                 sealing as Boolean) as Array<Dictionary>? {
        var result = [] as Array<Dictionary>;

        for (var i = 0; i < accounts.size(); i++) {
            var account = accounts[i];
            var secret = account["secret"];
            if (!(secret instanceof String)) {
                return null;
            }

            var changed = sealing
                ? CacheBox.seal(secret, key)
                : CacheBox.open(secret, key);
            if (changed == null) {
                return null;
            }

            var copy = {} as Dictionary;
            var keys = account.keys();
            for (var k = 0; k < keys.size(); k++) {
                copy[keys[k]] = account[keys[k]];
            }
            copy["secret"] = changed;
            result.add(copy);
        }

        return result;
    }

    // Everything the record holds, in a fixed order, as one string for the tag
    // to be taken over. Null if any of it is not the shape this app writes,
    // which makes the encoding double as the schema check.
    //
    // The count goes in ahead of the accounts so that a shorter list cannot be
    // read out of a longer one's bytes.
    static function canonicalEnvelope(fingerprint as Number, iv as String, encrypted as Boolean,
                                      localSealed as Boolean,
                                      accounts as Array<Dictionary>) as String? {
        var canonical = piece("n", fingerprint.toString())
            + piece("s", iv)
            + piece("b", encrypted ? "1" : "0")
            + piece("b", localSealed ? "1" : "0")
            + piece("n", accounts.size().toString());

        for (var i = 0; i < accounts.size(); i++) {
            var account = accounts[i];
            var record = canonicalRecord(account);
            var secret = account["secret"];
            if (record == null || !(secret instanceof String)) {
                return null;
            }
            canonical += record + piece("s", secret);
        }

        return canonical;
    }

    // One account, without its secret. Every field the app will later read back
    // and use unchecked — the digits, the period and the algorithm decide what
    // a seed produces just as much as the seed does, and the id is the only
    // thing that tells apart two accounts the vault is under no obligation to
    // keep distinct.
    static function canonicalRecord(account as Dictionary) as String? {
        var parts = [
            number(account, "id"),
            text(account, "name"),
            text(account, "issuer"),
            text(account, "type"),
            text(account, "algorithm"),
            number(account, "period"),
            number(account, "digits")
        ] as Array<String?>;

        var canonical = "";
        for (var i = 0; i < parts.size(); i++) {
            var part = parts[i];
            if (part == null) {
                return null;
            }
            canonical += part as String;
        }
        return canonical;
    }

    // Null rather than a default when the field is missing or the wrong type.
    // Encoding an absent field as an empty one would let a field be deleted
    // without disturbing the tag, and the code that reads it back casts without
    // checking.
    private static function text(account as Dictionary, key as String) as String? {
        var value = account[key];
        if (!(value instanceof String)) {
            return null;
        }
        return piece("s", value);
    }

    private static function number(account as Dictionary, key as String) as String? {
        var value = account[key];
        if (!(value instanceof Number)) {
            return null;
        }
        return piece("n", value.toString());
    }

    // Type tagged and length prefixed, so that the number 30 and the string
    // "30" are different bytes, and so that no two different records can encode
    // to the same ones by moving a boundary.
    private static function piece(type as String, value as String) as String {
        return type + value.length().toString() + ":" + value;
    }
}
