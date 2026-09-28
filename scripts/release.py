#!/usr/bin/env python3
"""Publish the tested bundle; called only by the manually dispatched release job."""
import argparse
import json
import os
import re
import subprocess
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('version')
    parser.add_argument('--dist', type=Path, default=Path('dist'))
    args = parser.parse_args()
    if not re.fullmatch(r'\d+\.\d+\.\d+(?:-[A-Za-z0-9.-]+)?', args.version):
        parser.error('Use a version such as 0.1.0 or 0.1.0-rc1.')
    bundles = list(args.dist.glob('*.tar.zst'))
    if len(bundles) != 1:
        parser.error('Expected exactly one tested bundle in dist.')
    repository = os.environ['GITHUB_REPOSITORY']
    commit = os.environ['GITHUB_SHA']
    info = json.loads((args.dist / 'build-info.json').read_text())
    url = f'https://github.com/{repository}/releases/download/{args.version}/{bundles[0].name}'
    notes = args.dist / 'release-notes.md'
    notes.write_text(
        f'Built and tested with {info["roc"]} and Zig {info["zig"]}.\n\n'
        'Prebuilt hosts: x64 and ARM64 macOS, Linux (musl), and Windows (MinGW). '
        'ARM64 Windows is cross-built; the other targets are executed in CI.\n\n'
        f'```roc\napp [main!] {{ pf: platform "{url}" }}\n```\n\n'
        'Use `roc --opt=speed app.roc`. Other Roc nightlies may have incompatible native ABIs.\n'
    )
    subprocess.run(['gh', 'release', 'create', args.version, str(bundles[0]),
                    str(args.dist / 'build-info.json'), '--repo', repository,
                    '--target', commit, '--title', args.version, '--generate-notes',
                    '--notes-file', str(notes)], check=True)


if __name__ == '__main__':
    main()
