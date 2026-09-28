#!/usr/bin/env python3
"""Build native host libraries and their runtime inputs (requires Zig 0.16.0)."""
import argparse
import json
import re
import subprocess
import tempfile
from pathlib import Path

from common import ROOT, TARGETS, install_runtime, native_target


def build(target):
    output = ROOT / 'platform' / 'targets' / target
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='roc-parallel-build-') as directory:
        runtime_files = install_runtime(Path(directory), output, target)
    host = 'host.lib' if target.endswith('mingw') else 'libhost.a'
    subprocess.run(['zig', 'build-lib', str(ROOT / 'platform/host.zig'),
                    '-target', TARGETS[target], '-lc', '-O', 'ReleaseSafe', '-fcompiler-rt',
                    f'-femit-bin={output / host}'], check=True)
    before = [name for name in runtime_files if name.endswith(('.o', '.obj'))]
    after = [name for name in runtime_files if name not in before]
    inputs = ', '.join([*(json.dumps(name) for name in before), json.dumps(host), 'app',
                        *(json.dumps(name) for name in after)])
    manifest = ROOT / 'platform/main.roc'
    text, count = re.subn(rf'{target}: \{{ inputs: \[.*?\] \}}',
                          lambda _: f'{target}: {{ inputs: [{inputs}] }}', manifest.read_text())
    if count != 1:
        raise RuntimeError(f'Missing platform target: {target}')
    manifest.write_text(text)
    print(f'Built {target}', flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group()
    group.add_argument('--target', choices=TARGETS)
    group.add_argument('--all', action='store_true')
    args = parser.parse_args()
    if subprocess.check_output(['zig', 'version'], text=True).strip() != '0.16.0':
        parser.error('Building the host requires Zig 0.16.0.')
    targets = list(TARGETS) if args.all else [args.target or native_target()]
    if None in targets:
        parser.error('Unsupported host; choose --target explicitly.')
    for target in targets:
        build(target)


if __name__ == '__main__':
    main()
