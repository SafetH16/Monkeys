import urllib.request
import json
import ssl

ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

search_url = 'https://archive.org/advancedsearch.php?q=subject%3A%22lofi%22+AND+mediatype%3Aaudio&fl%5B%5D=identifier&sort%5B%5D=downloads+desc&output=json&rows=10'

req = urllib.request.Request(search_url, headers={'User-Agent': 'Mozilla/5.0'})
try:
    with urllib.request.urlopen(req, context=ctx) as response:
        data = json.loads(response.read().decode())
        docs = data['response']['docs']
        if not docs:
            print("No results found.")
            exit(1)
        
        identifier = docs[0]['identifier']
        print(f"Found identifier: {identifier}")
        
        meta_url = f'https://archive.org/metadata/{identifier}'
        meta_req = urllib.request.Request(meta_url, headers={'User-Agent': 'Mozilla/5.0'})
        with urllib.request.urlopen(meta_req, context=ctx) as meta_response:
            meta_data = json.loads(meta_response.read().decode())
            files = meta_data.get('files', [])
            mp3_file = None
            for f in files:
                if f.get('name', '').endswith('.mp3'):
                    mp3_file = f['name']
                    break
            
            if mp3_file:
                download_url = f"https://archive.org/download/{identifier}/{mp3_file}"
                print(f"Downloading {download_url}...")
                import urllib.parse
                download_url = urllib.parse.quote(download_url, safe=":/")
                req_dl = urllib.request.Request(download_url, headers={'User-Agent': 'Mozilla/5.0'})
                with urllib.request.urlopen(req_dl, context=ctx) as dl_res, open('lofi_beat.mp3', 'wb') as out_file:
                    out_file.write(dl_res.read())
                print("Download complete.")
            else:
                print("No mp3 file found in the item.")
except Exception as e:
    print(f"Error: {e}")
