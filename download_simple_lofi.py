import urllib.request, json, ssl, urllib.parse

ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

# Search for "lofi loop" or "chill beat"
search_url = 'https://archive.org/advancedsearch.php?q=subject%3A%22lofi+loop%22+OR+title%3A%22lofi+loop%22+AND+mediatype%3Aaudio&fl%5B%5D=identifier,title&sort%5B%5D=downloads+desc&output=json&rows=10'
req = urllib.request.Request(search_url, headers={'User-Agent': 'Mozilla/5.0'})
try:
    with urllib.request.urlopen(req, context=ctx) as response:
        data = json.loads(response.read().decode())
        docs = data['response']['docs']
        if not docs:
            # Fallback search
            search_url = 'https://archive.org/advancedsearch.php?q=subject%3A%22lofi%22+AND+subject%3A%22instrumental%22+AND+mediatype%3Aaudio&fl%5B%5D=identifier,title&sort%5B%5D=downloads+desc&output=json&rows=10'
            req = urllib.request.Request(search_url, headers={'User-Agent': 'Mozilla/5.0'})
            with urllib.request.urlopen(req, context=ctx) as response2:
                data = json.loads(response2.read().decode())
                docs = data['response']['docs']
                
        for doc in docs:
            identifier = doc['identifier']
            meta_url = f'https://archive.org/metadata/{identifier}'
            meta_req = urllib.request.Request(meta_url, headers={'User-Agent': 'Mozilla/5.0'})
            with urllib.request.urlopen(meta_req, context=ctx) as meta_response:
                meta_data = json.loads(meta_response.read().decode())
                for f in meta_data.get('files', []):
                    if f.get('name', '').endswith('.mp3') and int(f.get('size', 0)) < 8000000:
                        download_url = f"https://archive.org/download/{identifier}/{f['name']}"
                        download_url = urllib.parse.quote(download_url, safe=':/')
                        print(f"Downloading {download_url}...")
                        req_dl = urllib.request.Request(download_url, headers={'User-Agent': 'Mozilla/5.0'})
                        with urllib.request.urlopen(req_dl, context=ctx) as dl_res, open('Monkeys/bg_music.mp3', 'wb') as out_file:
                            out_file.write(dl_res.read())
                        print('Downloaded Monkeys/bg_music.mp3')
                        exit(0)
        print("No suitable track found.")
except Exception as e:
    print(e)
