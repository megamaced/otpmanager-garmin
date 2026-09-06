import Toybox.Application;
import Toybox.Lang;

// Caches the last successful fetch so the app opens straight into the account
// list, and still works when the phone is out of range. The cached secrets stay
// exactly as the server sent them: encrypted, when the vault has a password.
class AccountStore {

    private const STORAGE_KEY = "vault";

    private var _config as Config;
    private var _accounts as Array<Dictionary> = [] as Array<Dictionary>;
    private var _iv as String = "";
    private var _encrypted as Boolean = false;
    private var _loaded as Boolean = false;

    function initialize(config as Config) {
        _config = config;
        restore();
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

        var record = {
            "fingerprint" => _config.fingerprint(),
            "accounts" => _accounts,
            "iv" => _iv,
            "encrypted" => _encrypted
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

        _accounts = accounts as Array<Dictionary>;
        _iv = iv;
        _encrypted = encrypted;
        _loaded = true;
    }
}
