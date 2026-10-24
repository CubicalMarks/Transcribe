#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash -n scripts/build-app.sh scripts/build-dmg.sh scripts/release.sh scripts/lint.sh
plutil -lint resources/Info.plist resources/entitlements.plist
swift package dump-package >/dev/null
python3 - <<'PY'
from pathlib import Path
import ast
for path in Path('scripts').glob('*.py'):
    ast.parse(path.read_text(), filename=str(path))
for folder in ('Sources', 'Tests', 'scripts', 'resources'):
    for path in Path(folder).rglob('*'):
        if path.is_file():
            text = path.read_text()
            assert text.endswith('\n'), f'{path}: missing final newline'
            assert not any(line.endswith((' ', '\t')) for line in text.splitlines()), f'{path}: trailing whitespace'
print('Source and configuration checks passed.')
PY
