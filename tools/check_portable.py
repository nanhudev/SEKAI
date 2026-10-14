"""Check asset integrity after clone or pull; no third-party dependencies."""
import hashlib
import json
from pathlib import Path

root = Path(__file__).resolve().parents[1]
manifest = json.loads((root / 'docs/CLOUD_ASSETS.json').read_text(encoding='utf-8'))
errors = []
for row in manifest['files']:
    path = root / row['path']
    if not path.is_file():
        errors.append('Missing: ' + row['path'])
        continue
    digest = hashlib.file_digest(path.open('rb'), 'sha256').hexdigest()
    if digest != row['sha256']:
        errors.append('Changed or LFS pointer: ' + row['path'])
if errors:
    raise SystemExit('\n'.join(errors))
print(f"OK: {len(manifest['files'])} assets verified")
