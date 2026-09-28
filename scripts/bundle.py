#!/usr/bin/env python3
"""Bundle all six prebuilt targets, with build metadata and runtime licenses."""
import argparse
import json
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

from common import ROOT, ROC, TARGETS


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output-dir', type=Path, default=ROOT / 'dist')
    args = parser.parse_args()
    output = args.output_dir.resolve()
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='roc-parallel-bundle-') as directory:
        stage = Path(directory)
        sources = ROOT / 'platform'
        for source in sources.glob('*.roc'):
            shutil.copy2(source, stage)
        manifest = (stage / 'main.roc').read_text()
        for target in TARGETS:
            match = re.search(rf'{target}: \{{ inputs: \[(.*?)\] \}}', manifest)
            if not match:
                raise RuntimeError(f'Missing target: {target}')
            inputs = re.findall(r'"([^"]+)"', match[1])
            if not target.endswith('mac') and len(inputs) < 2:
                raise RuntimeError(f'Runtime inputs not built for {target}; run build.py --all.')
            for name in inputs:
                destination = stage / 'targets' / target / name
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(sources / 'targets' / target / name, destination)
        shutil.copy2(ROOT / 'LICENSE', stage)
        shutil.copytree(ROOT / 'licenses', stage / 'licenses')
        metadata = {
            'roc': subprocess.check_output([ROC, 'version'], text=True).strip(),
            'zig': subprocess.check_output(['zig', 'version'], text=True).strip(),
            'targets': list(TARGETS),
        }
        (stage / 'build-info.json').write_text(json.dumps(metadata, indent=2) + '\n')
        (output / 'build-info.json').write_text(json.dumps(metadata, indent=2) + '\n')
        files = ['main.roc'] + sorted(p.relative_to(stage).as_posix() for p in stage.rglob('*')
                                    if p.is_file() and p.name != 'main.roc')
        subprocess.run([ROC, 'bundle', *files, '--output-dir', str(output)], cwd=stage, check=True)


if __name__ == '__main__':
    main()
