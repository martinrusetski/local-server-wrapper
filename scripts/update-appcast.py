#!/usr/bin/env python3
import datetime
import email.utils
import pathlib
import sys
import xml.etree.ElementTree as ET

feed, version, build, archive, url, signature = sys.argv[1:]
namespace = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
ET.register_namespace('sparkle', namespace)
sparkle = lambda name: '{' + namespace + '}' + name
path = pathlib.Path(feed)
tree = ET.parse(path)
channel = tree.getroot().find('channel')
if channel is None:
    raise SystemExit('Appcast has no channel')
length = str(pathlib.Path(archive).stat().st_size)
for item in channel.findall('item'):
    previous = item.findtext(sparkle('version'))
    if previous == build:
        enclosure = item.find('enclosure')
        if (item.findtext(sparkle('shortVersionString')) == version and enclosure is not None
                and enclosure.get('url') == url and enclosure.get('length') == length
                and enclosure.get(sparkle('edSignature')) == signature):
            print('Appcast already contains this exact update')
            raise SystemExit(0)
        raise SystemExit('Build number already exists with different update data')
    if previous is None or not previous.isdecimal() or int(previous) > int(build):
        raise SystemExit('Build number must be greater than every existing update')
item = ET.Element('item')
ET.SubElement(item, 'title').text = version
ET.SubElement(item, 'pubDate').text = email.utils.format_datetime(datetime.datetime.now(datetime.timezone.utc), usegmt=True)
ET.SubElement(item, sparkle('version')).text = build
ET.SubElement(item, sparkle('shortVersionString')).text = version
ET.SubElement(item, sparkle('minimumSystemVersion')).text = '13.5'
ET.SubElement(item, 'enclosure', {'url': url, sparkle('edSignature'): signature, 'length': length, 'type': 'application/octet-stream'})
items = list(channel)
position = next((index for index, child in enumerate(items) if child.tag == 'item'), len(items))
channel.insert(position, item)
ET.indent(tree, space='  ')
temporary = path.with_suffix('.xml.tmp')
tree.write(temporary, encoding='utf-8', xml_declaration=True)
temporary.replace(path)
print(f'Appcast updated for {version}, build {build}')
