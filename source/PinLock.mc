import Toybox.ActivityMonitor;
import Toybox.Application;
import Toybox.Lang;
import Toybox.StringUtil;
import Toybox.Time;

// Garmin Pay's rule, reproduced: once the passcode is entered the wallet stays
// open for 24 hours, and only while the watch stays on the wrist. Connect IQ
// exposes neither the wallet nor a wrist sensor, but Garmin's own wording gives
// away what the firmware watches — the passcode comes back if you "remove the
// watch from your wrist or disable heart rate monitoring" — and the heart rate
// history is readable, with no permission and no manifest change.
//
// Holding the derived key here is what makes a grace period possible at all.
// It is the one copy of anything sensitive this app persists, it lives only
// while the unlock stands, and it is not in the .prg.
module PinLock {

    const GRACE_SECONDS = 86400;

    // The longest a watch can go without a usable heart rate reading and still
    // count as worn. A Venu 3S records one sample a minute, so this allows ten
    // consecutive failures — and it needs to, because on hardware roughly one
    // sample in eight comes back invalid while the watch is plainly being worn.
    //
    // It is also the slack in the rule: the watch can be off the wrist for up
    // to this long and be put back on without the unlock ending.
    const MAX_SAMPLE_GAP = 600;

    // History reaching back a whole day is a lot of samples to walk, and the
    // answer is decided by the first gap in almost every case.
    const MAX_SAMPLES = 2000;

    const KEY_SIZE = 32;
    const STORAGE_KEY = "pinUnlock";

    function remember(key as ByteArray) as Void {
        var hex = StringUtil.convertEncodedString(key, {
            :fromRepresentation => StringUtil.REPRESENTATION_BYTE_ARRAY,
            :toRepresentation => StringUtil.REPRESENTATION_STRING_HEX
        }) as String;

        var record = {
            "at" => Time.now().value(),
            "key" => hex
        };
        Application.Storage.setValue(STORAGE_KEY, record as Application.Storage.ValueType);
    }

    function forget() as Void {
        Application.Storage.deleteValue(STORAGE_KEY);
    }

    // The key from a still-valid unlock, or null when the PIN has to be typed
    // again. Anything that fails ends the unlock rather than ignoring it.
    function recall() as ByteArray? {
        var stored = Application.Storage.getValue(STORAGE_KEY);
        if (!(stored instanceof Dictionary)) {
            return null;
        }

        var at = stored["at"];
        var hex = stored["key"];
        if (!(at instanceof Number) || !(hex instanceof String)) {
            forget();
            return null;
        }

        // A clock wound backwards ends the unlock as surely as one run forward
        // past the grace: the elapsed time can no longer be trusted either way.
        var now = Time.now().value();
        if (now < at || now - at > GRACE_SECONDS) {
            forget();
            return null;
        }

        if (!wornSince(samplesSince(at), at, now)) {
            forget();
            return null;
        }

        var key = bytes(hex);
        if (key == null || key.size() != KEY_SIZE) {
            forget();
            return null;
        }
        return key;
    }

    // Samples newest first. Wear is credited only when a usable reading turns
    // up at least every MAX_SAMPLE_GAP seconds, all the way back to the unlock.
    // Running out of history proves nothing, so it locks — and the history does
    // not survive a power cycle, which is exactly when the app should ask again.
    //
    // An invalid sample counts as no reading rather than as a removed watch.
    // The optical sensor drops readings routinely on a wrist that never moved,
    // so treating one as evidence of removal locks the app at random; what
    // removal actually looks like is a run of them long enough to open a gap.
    function wornSince(samples as Array<HrSample>, since as Number, now as Number) as Boolean {
        var lastReading = now;
        var previous = now;

        for (var i = 0; i < samples.size(); i++) {
            var sample = samples[i];

            // History has to run backwards; anything else is not a timeline.
            if (sample.at > previous) {
                return false;
            }
            previous = sample.at;

            if (!sample.isValid()) {
                continue;
            }
            if (lastReading - sample.at > MAX_SAMPLE_GAP) {
                return false;
            }
            if (sample.at <= since) {
                return true;
            }
            lastReading = sample.at;
        }

        return false;
    }

    function samplesSince(since as Number) as Array<HrSample> {
        var samples = [] as Array<HrSample>;
        if (!(ActivityMonitor has :getHeartRateHistory)) {
            return samples;
        }

        var span = Time.now().value() - since + MAX_SAMPLE_GAP;
        var iterator = ActivityMonitor.getHeartRateHistory(new Time.Duration(span), true);

        for (var i = 0; i < MAX_SAMPLES; i++) {
            var sample = iterator.next();
            if (sample == null) {
                break;
            }
            var when = sample.when;
            if (when == null) {
                break;
            }
            samples.add(new HrSample(sample.heartRate, when.value()));
        }

        return samples;
    }

    function bytes(hex as String) as ByteArray? {
        try {
            return StringUtil.convertEncodedString(hex, {
                :fromRepresentation => StringUtil.REPRESENTATION_STRING_HEX,
                :toRepresentation => StringUtil.REPRESENTATION_BYTE_ARRAY
            }) as ByteArray;
        } catch (e) {
            return null;
        }
    }
}

// One heart rate reading, reduced to the two things the rule cares about.
// Separating it from the SDK iterator is what makes the rule testable: the
// simulator will not put a watch on and take it off again.
class HrSample {

    var heartRate as Number?;
    var at as Number;

    function initialize(heartRate as Number?, at as Number) {
        self.heartRate = heartRate;
        self.at = at;
    }

    // An explicitly invalid sample is what a watch off the wrist records, and
    // it is also what one with heart rate monitoring turned off records.
    function isValid() as Boolean {
        var rate = heartRate;
        return rate != null && rate != ActivityMonitor.INVALID_HR_SAMPLE && rate > 0;
    }
}
