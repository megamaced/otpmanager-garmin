import Toybox.Application;
import Toybox.Lang;

// Caches the last successful fetch so the app opens straight into the account
// list, and still works when the phone is out of range. A vault with a password
// sends ciphertext, which is cached as it arrived; a vault without one sends
// seeds, which are encrypted under the PIN key first — see CacheBox.
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

        // Sealed, so the cache cannot be read here — but whether its secrets
        // are in the clear can be seen without any key, and a PIN that only
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

        var accounts = _accounts;
        var localSealed = false;

        // Only a passwordless vault needs this. Anything else is already
        // ciphertext whose key lives inside the seal.
        var key = _config.localKey();
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

        var record = {
            "fingerprint" => _config.fingerprint(),
            "accounts" => accounts,
            "iv" => _iv,
            "encrypted" => _encrypted,
            "localSealed" => localSealed
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

        // Secrets encrypted locally under the PIN key when they were cached.
        // Without the key they are unreadable, which is the point — drop the
        // cache rather than keep something that cannot be used.
        var localSealed = isSealedLocally(cached);
        if (localSealed) {
            var key = _config.localKey();
            var opened = key == null
                ? null
                : withSecrets(accounts as Array<Dictionary>, key as ByteArray, false);
            if (opened == null) {
                Application.Storage.deleteValue(STORAGE_KEY);
                return;
            }
            accounts = opened as Array<Dictionary>;
        }

        _accounts = accounts as Array<Dictionary>;
        _iv = iv;
        _encrypted = encrypted;
        _loaded = true;

        // A cache written before there was a PIN, or by a version that did not
        // encrypt one, still holds a passwordless vault's seeds as the server
        // sent them. Rewriting it the moment the key is in hand is what stops
        // it outliving the PIN that was meant to cover it.
        if (!localSealed && !_encrypted && _config.localKey() != null) {
            persist();
        }
    }

    // Deletes a cached record whose secrets are held as the server sent them.
    // Takes no key: whether they were encrypted, and under whose, is recorded
    // in the clear beside them.
    private function discardIfPlaintext() as Void {
        var cached = Application.Storage.getValue(STORAGE_KEY);
        if (!(cached instanceof Dictionary)) {
            return;
        }

        var encrypted = cached["encrypted"];
        if (encrypted instanceof Boolean && encrypted) {
            // Server ciphertext, and the password that opens it is in the seal.
            return;
        }

        if (!isSealedLocally(cached)) {
            Application.Storage.deleteValue(STORAGE_KEY);
        }
    }

    // The stored record's own type, spelled out: a value that came back from
    // Application.Storage will not pass as a bare Dictionary.
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

            var record = canonicalRecord(account);
            var changed = sealing
                ? CacheBox.seal(secret, record, key)
                : CacheBox.open(secret, record, key);
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

    // Everything cached beside the secret, in a fixed order and with every
    // field length prefixed, so that no two different records can encode to the
    // same bytes. This is what the secret's tag is taken over, so editing any
    // of it invalidates the blob rather than quietly changing what the watch
    // shows — and the parameters matter as much as the name does, since the
    // digits, the period and the algorithm decide the code just as the seed
    // does. The id is what tells apart two accounts that are otherwise
    // identical, which nothing here stops the vault from holding.
    static function canonicalRecord(account as Dictionary) as String {
        var fields = ["id", "name", "issuer", "type", "algorithm", "period", "digits"] as Array<String>;

        var canonical = "";
        for (var i = 0; i < fields.size(); i++) {
            var value = text(account, fields[i]);
            canonical += value.length().toString() + ":" + value;
        }
        return canonical;
    }

    // Numbers as well as strings: the id, the period and the digits are counts.
    private static function text(account as Dictionary, key as String) as String {
        var value = account[key];
        if (value instanceof String) {
            return value;
        }
        if (value instanceof Number) {
            return value.toString();
        }
        return "";
    }
}
