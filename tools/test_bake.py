#!/usr/bin/env python3
"""Tests for the build-time tools. Run them with ./build.sh test, or:

    python3 -m unittest discover -s tools -p 'test_*.py'

The watch side of the seal has its own test, in source/Tests.mc, which opens a
blob this module's sealer produced. These cover the part that never reaches the
watch: turning local.properties into XML without corrupting a credential.
"""
import base64
import importlib
import pathlib
import sys
import tempfile
import unittest
from xml.etree import ElementTree

sys.path.insert(0, str(pathlib.Path(__file__).parent))
bake = importlib.import_module("bake-properties")
seal = importlib.import_module("seal")

TEMPLATE = """<resources>
    <properties>
        <property id="serverUrl" type="string"></property>
        <property id="otpPassword" type="string"></property>
        <property id="username" type="string"></property>
        <property id="appPassword" type="string"></property>
        <property id="sealed" type="string"></property>
        <property id="buildSource" type="string"></property>
    </properties>
</resources>
"""


def baked_value(values, key):
    xml = bake.bake(TEMPLATE, values)
    root = ElementTree.fromstring(xml)          # also asserts well-formedness
    for prop in root.iter("property"):
        if prop.get("id") == key:
            return prop.text or ""
    raise AssertionError(f"no property {key}")


class Baking(unittest.TestCase):

    def test_ampersand_survives_as_itself(self):
        # An unescaped & is not well-formed XML, so this used to fail the build
        # with an error naming neither the password nor the character.
        self.assertEqual(baked_value({"otpPassword": "a&b"}, "otpPassword"), "a&b")

    def test_angle_brackets_do_not_change_the_structure(self):
        nasty = "</property></properties><evil>x</evil>"
        self.assertEqual(baked_value({"otpPassword": nasty}, "otpPassword"), nasty)

    def test_quotes_and_non_ascii(self):
        for value in ('say "hi"', "pässwörd", "日本語", "a'b"):
            self.assertEqual(baked_value({"otpPassword": value}, "otpPassword"), value)

    def test_unknown_property_is_an_error(self):
        with self.assertRaises(KeyError):
            bake.bake(TEMPLATE, {"nosuchkey": "x"})


class Reading(unittest.TestCase):

    def read(self, text):
        with tempfile.TemporaryDirectory() as d:
            p = pathlib.Path(d) / "local.properties"
            p.write_text(text, encoding="utf-8")
            return bake.read(p)

    def test_key_whitespace_is_syntax_but_value_whitespace_is_data(self):
        # A password may legitimately end in a space. Trimming it silently
        # builds an app that cannot log in, and says nothing about why.
        values = self.read("  otpPassword  = hunter2 \nusername=alice\n")
        self.assertEqual(values["otpPassword"], " hunter2 ")
        self.assertEqual(values["username"], "alice")

    def test_only_the_first_equals_splits(self):
        self.assertEqual(self.read("appPassword=a=b=c\n")["appPassword"], "a=b=c")

    def test_comments_and_blanks_are_skipped(self):
        values = self.read("# pin=1234\n\n   \nusername=alice\n")
        self.assertEqual(values, {"username": "alice"})

    def test_a_value_may_be_empty(self):
        self.assertEqual(self.read("pin=\n")["pin"], "")


class BuildSource(unittest.TestCase):
    """The marker that tells a compiled-in credential from one an older version
    of the app left in the property store. Without it the two are
    indistinguishable, because until signing in existed the settings screen
    wrote the login name and the app password to these same properties."""

    def bake(self, local):
        with tempfile.TemporaryDirectory() as d:
            source = pathlib.Path(d) / "properties.xml"
            source.write_text(TEMPLATE, encoding="utf-8")
            out = pathlib.Path(d) / "out.xml"
            local_file = pathlib.Path(d) / "local.properties"
            local_file.write_text(local, encoding="utf-8")

            argv, original = sys.argv, bake.SOURCE
            sys.argv = ["bake-properties.py", "--out", str(out), str(local_file)]
            bake.SOURCE = source
            try:
                self.assertEqual(bake.main(), 0)
            finally:
                sys.argv, bake.SOURCE = argv, original

            root = ElementTree.fromstring(out.read_text(encoding="utf-8"))
            return {p.get("id"): (p.text or "") for p in root.iter("property")}

    def test_baked_credentials_are_marked(self):
        properties = self.bake("username=alice\nappPassword=app-pw\n")
        self.assertEqual(properties["buildSource"], "local")

    def test_a_sealed_build_is_marked_too(self):
        # Sealing blanks the username and app password, so the seal is the only
        # credential left to notice.
        properties = self.bake("username=alice\nappPassword=app-pw\n"
                               "otpPassword=hunter2\npin=1357\n")
        self.assertEqual(properties["username"], "")
        self.assertNotEqual(properties["sealed"], "")
        self.assertEqual(properties["buildSource"], "local")

    def test_a_build_with_no_credentials_is_not_marked(self):
        # Nothing to protect and nothing to tell apart: this build behaves like
        # a store build, and a sign-in on it records a server like any other.
        properties = self.bake("serverUrl=https://cloud.example.com\n")
        self.assertEqual(properties["buildSource"], "")


class Sealing(unittest.TestCase):

    def test_round_trips_through_the_blob_format(self):
        blob = base64.b64decode(seal.seal("alice", "app-pw", "hunter2", "1357",
                                          iterations=64))
        self.assertEqual(blob[0], seal.VERSION)
        self.assertEqual(blob[1], 4)
        self.assertEqual(len(blob) % seal.BLOCK, (2 + 4 + 32) % seal.BLOCK)

    def test_a_short_pin_is_refused(self):
        with self.assertRaises(ValueError):
            seal.seal("alice", "app-pw", "hunter2", "123")

    def test_a_non_numeric_pin_is_refused(self):
        with self.assertRaises(ValueError):
            seal.seal("alice", "app-pw", "hunter2", "12a4")


if __name__ == "__main__":
    unittest.main()
