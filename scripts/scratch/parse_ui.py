import xml.etree.ElementTree as ET

tree = ET.parse('scratch/view.xml')
root = tree.getroot()

def walk(node):
    text = node.attrib.get('text', '')
    desc = node.attrib.get('content-desc', '')
    bounds = node.attrib.get('bounds', '')
    if text or desc:
        print(f'text="{text}" desc="{desc}" bounds={bounds}')
    for child in node:
        walk(child)

walk(root)
