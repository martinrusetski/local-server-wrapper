#!/usr/bin/env python3
"""Regression checks for feed updates and the shared-tap cask renderer."""
import pathlib
import subprocess
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET

ROOT = pathlib.Path(__file__).resolve().parent.parent
NS = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'

class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.path = pathlib.Path(self.directory.name)
        self.feed = self.path / 'appcast.xml'
        self.feed.write_text('<rss version="2.0"><channel><title>Test</title></channel></rss>')
        self.archive = self.path / 'test.dmg'
        self.archive.write_bytes(b'test archive')

    def update(self, build='1', signature='signature'):
        return subprocess.run([sys.executable, str(ROOT / 'scripts/update-appcast.py'), str(self.feed), '0.1.0', build, str(self.archive), 'https://example.com/test.dmg', signature], capture_output=True)

    def test_metadata_matches_archive(self):
        self.assertEqual(self.update().returncode, 0)
        item = ET.parse(self.feed).find('./channel/item')
        self.assertEqual(item.findtext(NS + 'minimumSystemVersion'), '13.5')
        self.assertEqual(item.find('enclosure').get('length'), str(self.archive.stat().st_size))
        self.assertEqual(item.find('enclosure').get(NS + 'edSignature'), 'signature')

    def test_exact_retry_does_not_duplicate_or_rewrite(self):
        self.assertEqual(self.update().returncode, 0)
        original = self.feed.read_bytes()
        self.assertEqual(self.update().returncode, 0)
        self.assertEqual(original, self.feed.read_bytes())

    def test_conflicting_and_older_builds_preserve_feed(self):
        self.assertEqual(self.update('2').returncode, 0)
        original = self.feed.read_bytes()
        self.assertNotEqual(self.update('1').returncode, 0)
        self.assertNotEqual(self.update('2', 'different-signature').returncode, 0)
        self.assertEqual(original, self.feed.read_bytes())

    def test_cask_gets_real_checksum(self):
        import hashlib
        destination = self.path / 'Casks/local-server-wrapper.rb'
        subprocess.run([sys.executable, str(ROOT / 'scripts/update-cask.py'), '0.2.0', str(self.archive), str(destination)], check=True)
        rendered = destination.read_text()
        self.assertIn('version "0.2.0"', rendered)
        self.assertIn(hashlib.sha256(self.archive.read_bytes()).hexdigest(), rendered)
        self.assertIn('postflight_steps', rendered)

if __name__ == '__main__':
    unittest.main()
