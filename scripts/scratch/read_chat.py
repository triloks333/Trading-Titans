import urllib.request
import json
import os
import sys

sys.stdout.reconfigure(encoding='utf-8')

url = 'https://bftvimnhpoiuoyryyiff.supabase.co/rest/v1/chat_feed?select=*&order=created_at.desc&limit=30'
key = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJmdHZpbW5ocG9pdW95cnl5aWZmIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3OTg3NTU0NCwiZXhwIjoyMDk1NDUxNTQ0fQ.4axy676RkSAc7kUyQjCEAT_V46pyZxUsxVecan-c3mg'

req = urllib.request.Request(url, headers={'apikey': key, 'Authorization': 'Bearer ' + key})
try:
    with urllib.request.urlopen(req) as resp:
        data = json.loads(resp.read().decode())
        print(f"Total messages returned: {len(data)}")
        for d in reversed(data):
            print(f"[{d.get('created_at')}] {d.get('author_name')} (admin={d.get('author_is_admin')}): {d.get('body')} (media: {d.get('media_path')})")
except Exception as e:
    print(f"Error: {e}")
