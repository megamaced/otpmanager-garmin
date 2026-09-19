import Toybox.System;
import Toybox.ActivityMonitor;
import Toybox.Cryptography;
import Toybox.Lang;
import Toybox.StringUtil;
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

(:test)
function testOnlyHttpsUrlsAreAccepted(logger as Logger) as Boolean {
    Test.assertMessage(Config.isHttpsUrl("https://cloud.example.com"), "https should be accepted");
    Test.assertMessage(!Config.isHttpsUrl("http://cloud.example.com"), "plain http must be rejected");
    Test.assertMessage(!Config.isHttpsUrl("cloud.example.com"), "a bare host must be rejected");
    Test.assertMessage(!Config.isHttpsUrl(""), "an empty URL must be rejected");
    Test.assertMessage(!Config.isHttpsUrl("https://"), "a scheme with no host must be rejected");

    // URI schemes are case-insensitive.
    Test.assertMessage(Config.isHttpsUrl("HTTPS://cloud.example.com"), "an upper-case scheme is still https");
    Test.assertMessage(Config.isHttpsUrl("HtTpS://cloud.example.com"), "scheme case must not matter");
    Test.assertMessage(!Config.isHttpsUrl("HTTP://cloud.example.com"), "upper-case http is still not https");

    // Long enough to pass a naive prefix check, but with no authority.
    Test.assertMessage(!Config.isHttpsUrl("https:///"), "an empty authority must be rejected");
    Test.assertMessage(!Config.isHttpsUrl("https:///path"), "a path with no host must be rejected");
    Test.assertMessage(!Config.isHttpsUrl("https://?q=1"), "a query with no host must be rejected");
    Test.assertMessage(!Config.isHttpsUrl("https://#f"), "a fragment with no host must be rejected");
    Test.assertMessage(Config.isHttpsUrl("https://h"), "a one-character host is an authority");
    return true;
}

// GET /accounts returns accounts shared with the user alongside their own.
// A locked share is encrypted with the sharing password, not the vault key.
(:test)
function testSharedAndDeletedAccountsAreSkipped(logger as Logger) as Boolean {
    var api = new OtpManagerApi(new Config(), 0);
    var parsed = api.toAccounts([
        account("mine", false, null),
        account("shared", true, null),
        account("binned", false, "2026-01-01 00:00:00")
    ]);

    Test.assertEqual(parsed.size(), 1);
    Test.assertEqual(parsed[0]["name"] as String, "mine");
    return true;
}

(:test)
function testAccountsAreGroupedByIssuer(logger as Logger) as Boolean {
    var api = new OtpManagerApi(new Config(), 0);
    var parsed = api.toAccounts([
        issued("zoe", "Zulu"),
        issued("beta", "Authentik"),
        issued("adam", "aardvark"),
        issued("alpha", "authentik"),
        issued("solo", "")
    ]);

    // Case-insensitive by issuer, then by name; an account with no issuer
    // sorts under its own name rather than jumping to the front.
    var order = "";
    for (var i = 0; i < parsed.size(); i++) {
        order += (parsed[i]["name"] as String) + " ";
    }
    Test.assertEqual(order, "adam alpha beta solo zoe ");
    return true;
}

// Produced by tools/seal.py with a fixed salt and IV, so that the watch and the
// build-time sealer are checked against each other rather than each against
// itself. A low iteration count keeps the test quick; the count lives in the
// blob, so the derivation does not care what it is.
//
//   ./tools/seal.py --pin 1357 --username alice --app-password app-pw \
//       --otp-password hunter2 --iterations 1000 \
//       --salt 000102030405060708090a0b0c0d0e0f \
//       --iv 0f0e0d0c0b0a09080706050403020100
const SEALED_BY_PYTHON =
    "AgQAAAPoAAECAwQFBgcICQoLDA0ODw8ODQwLCgkIBwYFBAMCAQAmYEa/w4e8BJ3GIwpVtQKqyg5KpAut8EhGLtiJqQq6ww==";

// The same credentials in the format that predates the login flow, when the
// username was typed into the settings screen instead of being signed in for.
const SEALED_VERSION_1 =
    "AQQAAAPoAAECAwQFBgcICQoLDA0ODw8ODQwLCgkIBwYFBAMCAQAwKz0ibkPuj1V2xhhoQp4WZURiEvltK3QftJILqyd47g==";

(:test)
function testOpensABlobSealedByTheBuildTools(logger as Logger) as Boolean {
    var blob = Sealed.parse(SEALED_BY_PYTHON);
    Test.assertMessage(blob != null, "the python blob did not parse");

    var parsed = blob as SealedBlob;
    Test.assertEqual(parsed.pinLength, 4);
    Test.assertEqual(parsed.iterations, 1000);

    var credentials = openWith(parsed, "1357");
    Test.assertMessage(credentials != null, "the right PIN did not open the blob");
    Test.assertEqual((credentials as Credentials).username, "alice");
    Test.assertEqual((credentials as Credentials).appPassword, "app-pw");
    Test.assertEqual((credentials as Credentials).otpPassword, "hunter2");
    return true;
}

// A blob from before the login flow cannot say who it belongs to, and the app
// treats one as no credentials at all rather than guessing at a username.
(:test)
function testBlobsFromTheOldFormatAreRejected(logger as Logger) as Boolean {
    Test.assertMessage(Sealed.parse(SEALED_VERSION_1) == null,
        "a version 1 blob must not parse as a version 2 one");
    return true;
}

(:test)
function testSealedBlobRejectsTheWrongPin(logger as Logger) as Boolean {
    var blob = Sealed.parse(SEALED_BY_PYTHON) as SealedBlob;

    // Adjacent, and the same length: nothing about a wrong PIN should be
    // easier to guess from how it fails.
    Test.assertMessage(openWith(blob, "1358") == null, "a wrong PIN opened the blob");
    Test.assertMessage(openWith(blob, "0000") == null, "a wrong PIN opened the blob");
    return true;
}

// Round trip through the watch's own sealer, driven exactly as the app drives
// it: derive a key from the PIN, then seal under it.
(:test)
function testSealRoundTripsOnTheWatch(logger as Logger) as Boolean {
    var salt = Sealed.salt();
    var key = derive("86420", salt, Sealed.ITERATIONS);

    var encoded = Sealed.sealWithKey(
        new Credentials("alice@example.com", "nextcloud-app-password", "vault-password"),
        5, salt, Sealed.iv(), key);
    Test.assertMessage(encoded != null, "sealing failed");

    var blob = Sealed.parse(encoded as String);
    Test.assertMessage(blob != null, "the watch produced a blob it cannot parse");

    var parsed = blob as SealedBlob;
    Test.assertEqual(parsed.pinLength, 5);
    Test.assertEqual(parsed.iterations, Sealed.ITERATIONS);

    var credentials = openWith(parsed, "86420");
    Test.assertMessage(credentials != null, "the PIN just used did not open the blob");
    Test.assertEqual((credentials as Credentials).username, "alice@example.com");
    Test.assertEqual((credentials as Credentials).appPassword, "nextcloud-app-password");
    Test.assertEqual((credentials as Credentials).otpPassword, "vault-password");

    Test.assertMessage(openWith(parsed, "86421") == null, "a wrong PIN opened the blob");
    return true;
}

(:test)
function testOnlyFourToEightDigitsAreAPin(logger as Logger) as Boolean {
    Test.assertMessage(Sealed.isPin("1234"), "four digits is a PIN");
    Test.assertMessage(Sealed.isPin("12345678"), "eight digits is a PIN");
    Test.assertMessage(!Sealed.isPin("123"), "three digits is too short");
    Test.assertMessage(!Sealed.isPin("123456789"), "nine digits is too long");
    Test.assertMessage(!Sealed.isPin("12a4"), "a letter is not a digit");
    Test.assertMessage(!Sealed.isPin(""), "an empty PIN is not a PIN");
    return true;
}

// What Nextcloud returns from /login/v2/poll once the wearer has granted
// access, and the several shapes it can be that mean it has not.
(:test)
function testPollResponseYieldsCredentials(logger as Logger) as Boolean {
    var credentials = NcLogin.signInFrom({
        "server" => "https://cloud.example.com",
        "loginName" => "alice@example.com",
        "appPassword" => "aBcDe-fGhIj-kLmNo-pQrSt-uVwXy"
    });

    Test.assertMessage(credentials != null, "a complete poll response should yield credentials");
    Test.assertEqual((credentials as SignIn).username, "alice@example.com");
    Test.assertEqual((credentials as SignIn).appPassword, "aBcDe-fGhIj-kLmNo-pQrSt-uVwXy");
    return true;
}

(:test)
function testIncompletePollResponsesAreRejected(logger as Logger) as Boolean {
    Test.assertMessage(NcLogin.signInFrom(null) == null,
        "an empty body is not a sign-in");
    Test.assertMessage(NcLogin.signInFrom("<html>") == null,
        "a body that is not JSON is not a sign-in");
    Test.assertMessage(NcLogin.signInFrom({ "loginName" => "alice" }) == null,
        "a response with no app password is not a sign-in");
    Test.assertMessage(NcLogin.signInFrom({ "appPassword" => "secret" }) == null,
        "a response with no login name is not a sign-in");
    Test.assertMessage(NcLogin.signInFrom({ "loginName" => "", "appPassword" => "secret" }) == null,
        "an empty login name is not a sign-in");
    return true;
}

// An app password belongs to the server that issued it. Origin is compared
// rather than the whole URL: Nextcloud can live in a subdirectory and its own
// idea of its address need not match what was typed character for character.
(:test)
function testOriginIgnoresPathAndCase(logger as Logger) as Boolean {
    assertText(Config.originOf("https://Cloud.Example.COM/nextcloud"), "https://cloud.example.com");
    assertText(Config.originOf("https://cloud.example.com:8443/x?y#z"), "https://cloud.example.com:8443");
    Test.assertMessage(Config.originOf("http://cloud.example.com") == null, "plain http has no usable origin");
    Test.assertMessage(Config.originOf("not a url") == null, "a non-URL has no origin");

    Test.assertMessage(Config.sameOrigin("https://a.example.com/nextcloud", "https://A.EXAMPLE.COM"),
        "path and case must not make two origins differ");
    Test.assertMessage(!Config.sameOrigin("https://a.example.com", "https://b.example.com"),
        "a different host is a different origin");
    Test.assertMessage(!Config.sameOrigin("https://a.example.com", "https://a.example.com.evil.net"),
        "a suffix match is not an origin match");
    Test.assertMessage(!Config.sameOrigin("https://a.example.com:8443", "https://a.example.com"),
        "a different port is a different origin");
    return true;
}

// Login Flow v2 names the server that issued the credentials, and a response
// that does not is not one to store.
(:test)
function testPollResponseMustNameItsServer(logger as Logger) as Boolean {
    Test.assertMessage(NcLogin.signInFrom({
        "loginName" => "alice", "appPassword" => "secret"
    }) == null, "a response with no server is not a sign-in");

    Test.assertMessage(NcLogin.signInFrom({
        "server" => "http://cloud.example.com", "loginName" => "alice", "appPassword" => "secret"
    }) == null, "a server that is not https is not a sign-in");
    return true;
}

// A vault password typed into the settings screen while a seal already holds
// one. Both the keypad path and the resumed-unlock path run through this.
(:test)
function testPendingVaultPasswordReplacesTheSealedOne(logger as Logger) as Boolean {
    var current = new Credentials("alice", "app-pw", "old-vault");

    var updated = Credentials.replacingOtpPassword(current, "new-vault");
    Test.assertMessage(updated != null, "a different pending password must replace the sealed one");
    Test.assertEqual((updated as Credentials).otpPassword, "new-vault");
    Test.assertEqual((updated as Credentials).username, "alice");
    Test.assertEqual((updated as Credentials).appPassword, "app-pw");

    Test.assertMessage(Credentials.replacingOtpPassword(current, "") == null,
        "an empty settings field is not a change");
    Test.assertMessage(Credentials.replacingOtpPassword(current, "old-vault") == null,
        "the same password again is not a change");
    return true;
}

// A vault with no password sends base32 seeds in the clear, and caching those
// verbatim handed every one of them to anyone who copied watch storage.
(:test)
function testCachedSecretsRoundTripUnderThePinKey(logger as Logger) as Boolean {
    var key = derive("2468", Sealed.salt(), 64);

    var sealed = CacheBox.seal(RFC_SECRET_SHA1, record(1, "alice", "GitHub"), key);
    Test.assertMessage(sealed != null, "encrypting a cached secret failed");
    Test.assertMessage(!(sealed as String).equals(RFC_SECRET_SHA1),
        "the stored form must not be the seed itself");

    assertText(CacheBox.open(sealed as String, record(1, "alice", "GitHub"), key), RFC_SECRET_SHA1);
    return true;
}

(:test)
function testCachedSecretsNeedTheRightKey(logger as Logger) as Boolean {
    var salt = Sealed.salt();
    var sealed = CacheBox.seal(RFC_SECRET_SHA1, record(1, "alice", ""), derive("2468", salt, 64)) as String;

    Test.assertMessage(CacheBox.open(sealed, record(1, "alice", ""), derive("1357", salt, 64)) == null,
        "a wrong key must not yield a seed");
    Test.assertMessage(CacheBox.open("AAAA", record(1, "alice", ""), derive("2468", salt, 64)) == null,
        "a blob too short to hold an IV and a tag must be rejected");
    return true;
}

// Every byte of the blob is covered by the tag, so an edited cache is refused
// outright rather than decrypted into a code that is quietly wrong.
(:test)
function testTamperedCachedSecretsAreRejected(logger as Logger) as Boolean {
    var key = derive("2468", Sealed.salt(), 64);
    var sealed = CacheBox.seal(RFC_SECRET_SHA1, record(1, "alice", ""), key) as String;
    var bytes = CacheBox.decode(sealed) as ByteArray;

    // The IV, a ciphertext byte, and the tag itself.
    var at = [0, CacheBox.IV_SIZE + 1, bytes.size() - 1] as Array<Number>;
    for (var i = 0; i < at.size(); i++) {
        var edited = bytes.slice(0, bytes.size());
        edited[at[i]] = edited[at[i]] ^ 0x40;

        Test.assertMessage(CacheBox.open(base64(edited), record(1, "alice", ""), key) == null,
            "a blob edited at byte " + at[i].toString() + " must not open");
    }

    // Truncation, which changes no byte that is left.
    Test.assertMessage(
        CacheBox.open(base64(bytes.slice(0, bytes.size() - 1)), record(1, "alice", ""), key) == null,
        "a truncated blob must not open");
    return true;
}

// The tag covers the record the secret was written for, so a blob cannot be
// moved to another account, and the parameters that turn a seed into a code
// cannot be edited underneath it.
(:test)
function testCachedSecretsAreTiedToTheirWholeRecord(logger as Logger) as Boolean {
    var key = derive("2468", Sealed.salt(), 64);
    var sealed = CacheBox.seal(RFC_SECRET_SHA1, record(1, "alice", "GitHub"), key) as String;

    Test.assertMessage(CacheBox.open(sealed, record(2, "alice", "GitHub"), key) == null,
        "a blob must not open against another account's id");
    Test.assertMessage(CacheBox.open(sealed, record(1, "alice", "GitLab"), key) == null,
        "a blob must not open under a different issuer");

    // Everything that decides what the code comes out as.
    var shifted = cached(1, "alice", "GitHub");
    shifted["digits"] = 8;
    Test.assertMessage(CacheBox.open(sealed, AccountStore.canonicalRecord(shifted), key) == null,
        "editing the digits must invalidate the blob");

    shifted = cached(1, "alice", "GitHub");
    shifted["algorithm"] = "SHA256";
    Test.assertMessage(CacheBox.open(sealed, AccountStore.canonicalRecord(shifted), key) == null,
        "editing the algorithm must invalidate the blob");

    shifted = cached(1, "alice", "GitHub");
    shifted["period"] = 60;
    Test.assertMessage(CacheBox.open(sealed, AccountStore.canonicalRecord(shifted), key) == null,
        "editing the period must invalidate the blob");

    shifted = cached(1, "alice", "GitHub");
    shifted["type"] = "hotp";
    Test.assertMessage(CacheBox.open(sealed, AccountStore.canonicalRecord(shifted), key) == null,
        "editing the type must invalidate the blob");
    return true;
}

// Length prefixes, so that no two different records encode to the same bytes:
// without them an issuer and a name could be re-cut to name a different pair.
(:test)
function testTheCanonicalRecordCannotBeReCut(logger as Logger) as Boolean {
    var encoded = AccountStore.canonicalRecord(cached(1, "alice", "GitHub"));

    Test.assertMessage(!AccountStore.canonicalRecord(cached(1, "ceGitHub", "Ali")).equals(encoded),
        "moving the boundary between two fields must change the record");
    Test.assertMessage(!AccountStore.canonicalRecord(cached(1, "", "aliceGitHub")).equals(encoded),
        "an empty field must not vanish from the record");
    return true;
}

// One IV per cache would have made two accounts with the same seed encrypt to
// the same bytes, which is a leak the cache does not have to have.
(:test)
function testEachCachedSecretGetsItsOwnIv(logger as Logger) as Boolean {
    var key = derive("2468", Sealed.salt(), 64);

    var first = CacheBox.seal(RFC_SECRET_SHA1, record(1, "alice", ""), key) as String;
    var second = CacheBox.seal(RFC_SECRET_SHA1, record(1, "alice", ""), key) as String;
    Test.assertMessage(!first.equals(second),
        "the same seed sealed twice must not produce the same blob");
    return true;
}

// Credentials stored before the app recorded which server issued them, which
// are discarded at startup. Two things that look identical in storage are not
// the same and must survive: a sideload's compiled-in credentials, and the seal
// it makes from them when a PIN is chosen on the watch.
(:test)
function testUnboundStoredCredentialsAreRecognised(logger as Logger) as Boolean {
    Test.assertMessage(CredentialStore.isUnbound(true, "", false),
        "a stored credential naming no server, in a build that compiled none in, is unbound");
    Test.assertMessage(!CredentialStore.isUnbound(true, "", true),
        "a sideload's own seal names no server and never could");
    Test.assertMessage(!CredentialStore.isUnbound(true, "https://cloud.example.com", false),
        "a credential that names its server is bound");
    Test.assertMessage(!CredentialStore.isUnbound(false, "", false),
        "an empty store has nothing to discard");
    return true;
}

// An account as it is held in the cache, and its canonical encoding.
function cached(id as Number, name as String, issuer as String) as Dictionary {
    return {
        "id" => id,
        "name" => name,
        "issuer" => issuer,
        "secret" => RFC_SECRET_SHA1,
        "type" => "totp",
        "period" => 30,
        "algorithm" => "SHA1",
        "digits" => 6
    };
}

function record(id as Number, name as String, issuer as String) as String {
    return AccountStore.canonicalRecord(cached(id, name, issuer));
}

function base64(bytes as ByteArray) as String {
    return StringUtil.convertEncodedString(bytes, {
        :fromRepresentation => StringUtil.REPRESENTATION_BYTE_ARRAY,
        :toRepresentation => StringUtil.REPRESENTATION_STRING_BASE64
    }) as String;
}

(:test)
function testMalformedBlobsAreRejected(logger as Logger) as Boolean {
    Test.assertMessage(Sealed.parse("") == null, "an empty blob must be rejected");
    Test.assertMessage(Sealed.parse("not base64 at all !!") == null, "junk must be rejected");
    Test.assertMessage(Sealed.parse("AQQAAAPoAAEC") == null, "a truncated blob must be rejected");
    return true;
}

// The Garmin Pay rule: unlocked for 24 hours, and only while worn. Samples
// arrive newest first, so the walk runs backwards towards the unlock.
//
// The shape of these cases comes from what a Venu 3S actually records: one
// sample a minute, and about seven in every sixty invalid while the watch is
// being worn normally.
(:test)
function testWearIsCreditedOnlyWhenUnbroken(logger as Logger) as Boolean {
    var now = 10000;
    var since = now - 3600;

    Test.assertMessage(PinLock.wornSince(worn(now, since - 60, 60), since, now),
        "a sample a minute back past the unlock is continuous wear");
    Test.assertMessage(!PinLock.wornSince([] as Array<HrSample>, since, now),
        "no history at all cannot prove wear");
    return true;
}

// The bug this rule was first written with: a dropped optical reading is not a
// removed watch, and on hardware they are common enough that treating one as
// removal locks the app on almost every launch.
(:test)
function testDroppedReadingsDoNotEndTheUnlock(logger as Logger) as Boolean {
    var now = 10000;
    var since = now - 3600;

    var samples = worn(now, since - 60, 60);
    samples[0].heartRate = ActivityMonitor.INVALID_HR_SAMPLE;
    samples[7].heartRate = ActivityMonitor.INVALID_HR_SAMPLE;
    samples[8].heartRate = null;
    samples[20].heartRate = ActivityMonitor.INVALID_HR_SAMPLE;
    Test.assertMessage(PinLock.wornSince(samples, since, now),
        "scattered invalid samples, including the newest, are still wear");
    return true;
}

(:test)
function testWearEndsAtAGapOrASustainedOutage(logger as Logger) as Boolean {
    var now = 10000;
    var since = now - 3600;

    var stale = [new HrSample(60, now - 1200)] as Array<HrSample>;
    Test.assertMessage(!PinLock.wornSince(stale, since, now),
        "a watch with no recent reading is not on a wrist now");

    // Worn since, but with the watch off for half an hour in the middle.
    var interrupted = worn(now, now - 900, 60);
    interrupted.addAll(worn(now - 2700, since - 60, 60));
    Test.assertMessage(!PinLock.wornSince(interrupted, since, now),
        "a gap in the middle must end the unlock");

    // What taking the watch off looks like: not one invalid sample but a run of
    // them, long enough that no usable reading turns up for MAX_SAMPLE_GAP.
    var removed = worn(now, since - 60, 60);
    for (var i = 3; i < 16; i++) {
        removed[i].heartRate = ActivityMonitor.INVALID_HR_SAMPLE;
    }
    Test.assertMessage(!PinLock.wornSince(removed, since, now),
        "a sustained run of invalid samples must end the unlock");
    return true;
}

(:test)
function testHistoryThatStopsShortProvesNothing(logger as Logger) as Boolean {
    var now = 10000;
    var since = now - 3600;

    // Continuous, recent, but only reaching back half way: the rest is unknown,
    // and unknown has to mean locked.
    Test.assertMessage(!PinLock.wornSince(worn(now, now - 1800, 60), since, now),
        "history ending before the unlock cannot prove wear");
    return true;
}

// Valid samples every `spacing` seconds, newest first, from `newest` back to
// `oldest` inclusive.
function worn(newest as Number, oldest as Number, spacing as Number) as Array<HrSample> {
    var samples = [] as Array<HrSample>;
    for (var at = newest; at >= oldest; at -= spacing) {
        samples.add(new HrSample(65, at));
    }
    return samples;
}

// Test.assertEqual refuses a nullable first argument, and every one of these
// returns null for the failure case it is being checked against.
function assertText(actual as String?, expected as String) as Void {
    Test.assertMessage(actual != null, "expected '" + expected + "', got null");
    Test.assertEqual(actual as String, expected);
}

function openWith(blob as SealedBlob, pin as String) as Credentials? {
    return blob.open(derive(pin, blob.salt, blob.iterations));
}

// The app spreads this over a timer so the watchdog never sees a long block of
// computation; a test has nothing to yield to.
function derive(pin as String, salt as ByteArray, iterations as Number) as ByteArray {
    var derivation = new KeyDerivation(pin, salt, iterations);
    while (!derivation.isDone()) {
        derivation.step(500);
    }
    return derivation.key();
}

function issued(name as String, issuer as String) as Dictionary {
    var a = account(name, false, null);
    a["issuer"] = issuer;
    return a;
}

function account(name as String, shared as Boolean, deletedAt as String?) as Dictionary {
    return {
        "name" => name,
        "issuer" => "Example",
        "secret" => RFC_SECRET_SHA1,
        "type" => "totp",
        "period" => 30,
        "algorithm" => "SHA1",
        "digits" => 6,
        "isShared" => shared,
        "deletedAt" => deletedAt
    };
}


// Not a pass/fail test: the number it logs is the only measurement of what a
// PIN entry costs, and the thing to look at before changing Sealed.ITERATIONS.
// The simulator runs on the workstation's CPU, so treat it as a floor — the
// watch is several times slower, and the ring on the PIN screen is the real
// measurement.
(:test)
function testKeyDerivationCost(logger as Logger) as Boolean {
    var salt = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15]b;

    var start = System.getTimer();
    var derivation = new KeyDerivation("1234", salt, Sealed.ITERATIONS);
    while (!derivation.isDone()) {
        derivation.step(500);
    }
    var elapsed = System.getTimer() - start;

    logger.debug(Sealed.ITERATIONS.toString() + " rounds in " + elapsed.toString() + " ms (simulator)");
    Test.assertEqual(derivation.key().size(), 32);
    return true;
}
