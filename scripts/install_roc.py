#!/usr/bin/env python3
"""Install one resolved Roc nightly in CI, shared across every job."""
import argparse
import os
import platform
import subprocess
import tarfile
import tempfile
import zipfile
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('tag')
    args = parser.parse_args()
    machine = platform.machine().lower()
    arm = machine in ('arm64', 'aarch64')
    if machine not in ('arm64', 'aarch64', 'amd64', 'x86_64'):
        parser.error('Unsupported architecture.')
    system = platform.system()
    names = {'Darwin': 'macos_apple_silicon' if arm else 'macos_x86_64',
             'Linux': 'linux_arm64' if arm else 'linux_x86_64',
             'Windows': 'windows_arm64' if arm else 'windows_x86_64'}
    name = names[system]
    extension = 'zip' if system == 'Windows' else 'tar.gz'
    destination = Path(os.environ['RUNNER_TEMP']) / 'roc-toolchain'
    destination.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as directory:
        subprocess.run(['gh', 'release', 'download', args.tag, '--repo', 'roc-lang/nightlies',
                        '--pattern', f'roc_nightly-{name}-*.{extension}', '--dir', directory], check=True)
        archives = list(Path(directory).glob(f'*.{extension}'))
        if len(archives) != 1:
            raise RuntimeError('Expected exactly one compiler archive.')
        if extension == 'zip':
            with zipfile.ZipFile(archives[0]) as archive:
                archive.extractall(destination)
        else:
            with tarfile.open(archives[0]) as archive:
                archive.extractall(destination, filter='data')
    executables = list(destination.rglob('roc.exe' if system == 'Windows' else 'roc'))
    executables = [path for path in executables if path.is_file()]
    if len(executables) != 1:
        raise RuntimeError('Expected exactly one Roc executable.')
    with open(os.environ['GITHUB_PATH'], 'a', encoding='utf-8') as file:
        file.write(str(executables[0].parent) + '\n')
    subprocess.run([str(executables[0]), 'version'], check=True)


if __name__ == '__main__':
    main()
