#!/usr/bin/env python3
"""Render the reviewed cask template with a real release version and archive hash."""
import hashlib
import pathlib
import re
import sys
version, archive, destination = sys.argv[1:]
if not re.fullmatch(r'\d+\.\d+\.\d+', version):
    raise SystemExit('Expected a stable semantic version')
root = pathlib.Path(__file__).resolve().parent.parent
text = (root / 'Casks/local-server-wrapper.rb').read_text()
text = re.sub(r'  version ".*"', f'  version "{version}"', text, count=1)
checksum = hashlib.file_digest(open(archive, 'rb'), 'sha256').hexdigest() if hasattr(hashlib, 'file_digest') else hashlib.sha256(pathlib.Path(archive).read_bytes()).hexdigest()
text = re.sub(r'  sha256 ".*"', f'  sha256 "{checksum}"', text, count=1)
pathlib.Path(destination).parent.mkdir(parents=True, exist_ok=True)
pathlib.Path(destination).write_text(text)
