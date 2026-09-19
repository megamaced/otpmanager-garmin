import Toybox.Application;
import Toybox.Lang;

// Caches the last successful fetch so the app opens straight into the account
// list, and still works when the phone is out of range. The cached secrets stay
// exactly as the server sent them: encrypted, when the vault has a password.
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
        var localIv = "";

        // Only a passwordless vault needs this. Anything else is already
        // ciphertext whose key lives inside the seal.
        var key = _config.localKey();
        if (!_encrypted && key != null) {
            var iv = Sealed.iv();
            var sealedAccounts = withSecrets(_accounts, key, iv, true);
            if (sealedAccounts != null) {
                accounts = sealedAccounts as Array<Dictionary>;
                localIv = CacheBox.toHex(iv);
            }
        }

        var record = {
            "fingerprint" => _config.fingerprint(),
            "accounts" => accounts,
            "iv" => _iv,
            "encrypted" => _encrypted,
            "localIv" => localIv
        };
        Application.Storage.setValue(STORAGE_KEY, record as Application.Storage.ValueType);
    }

    private function restore() as Void {
        var cached = Application.Storage.getValue(STORAGE_KEY);
        if (!(cached instanceof Dictionary)) {
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
        var localIv = cached["localIv"];
        if (localIv instanceof String && !localIv.equals("")) {
            var key = _config.localKey();
            var ivBytes = CacheBox.fromHex(localIv);
            var opened = key == null || ivBytes == null
                ? null
                : withSecrets(accounts as Array<Dictionary>, key as ByteArray,
                    ivBytes as ByteArray, false);
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
    }

    // The same account list with every secret run through CacheBox one way or
    // the other. Null if any of them fails, because a cache that is half
    // readable is worse than none: the failure would surface later as a wrong
    // code rather than as a missing one.
    private function withSecrets(accounts as Array<Dictionary>, key as ByteArray,
                                 iv as ByteArray, sealing as Boolean) as Array<Dictionary>? {
        var result = [] as Array<Dictionary>;

        for (var i = 0; i < accounts.size(); i++) {
            var account = accounts[i];
            var secret = account["secret"];
            if (!(secret instanceof String)) {
                return null;
            }

            var changed = sealing
                ? CacheBox.encrypt(secret, key, iv)
                : CacheBox.decrypt(secret, key, iv);
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
}
