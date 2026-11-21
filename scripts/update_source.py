#!/usr/bin/env python3
"""Atualiza altstore/apps.json (fonte AltStore/SideStore/Feather/FlareStore) com uma nova versão."""
import argparse, json, os
from datetime import datetime, timezone

ap = argparse.ArgumentParser()
ap.add_argument('--source', default='altstore/apps.json')
ap.add_argument('--version', required=True)
ap.add_argument('--build', required=True)
ap.add_argument('--ipa', required=True, help='caminho local do .ipa (para o tamanho)')
ap.add_argument('--url', required=True, help='URL de download do .ipa')
ap.add_argument('--notes', default='')
ap.add_argument('--keep', type=int, default=15)
a = ap.parse_args()

with open(a.source, encoding='utf-8') as f:
    src = json.load(f)
app = src['apps'][0]
now = datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
size = os.path.getsize(a.ipa)
notes = a.notes.strip() or f'Versão {a.version}'

entry = {
    'version': a.version,
    'buildVersion': a.build,
    'date': now,
    'localizedDescription': notes,
    'downloadURL': a.url,
    'size': size,
    'minOSVersion': '15.0',
}
versions = [v for v in app.get('versions', []) if v.get('version') != a.version]
app['versions'] = [entry] + versions[: a.keep - 1]
# Campos antigos lidos por apps de sideload mais simples (ESign, Feather antigo, etc.)
app.update({'version': a.version, 'versionDate': now, 'versionDescription': notes,
            'downloadURL': a.url, 'size': size})

with open(a.source, 'w', encoding='utf-8') as f:
    json.dump(src, f, ensure_ascii=False, indent=2)
    f.write('\n')
print(f'{a.source}: {a.version} ({size} bytes)')
