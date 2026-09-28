#!/usr/bin/env python3
"""Build and run the example and ownership checks, optionally through a bundle URL."""
import argparse
import functools
import http.server
import shutil
import subprocess
import tempfile
import threading
from pathlib import Path

from common import ROOT, ROC, TARGETS, native_target


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bundle', type=Path)
    parser.add_argument('--target', choices=TARGETS, default=native_target())
    parser.add_argument('--build-only', action='store_true')
    parser.add_argument('--output-dir', type=Path)
    args = parser.parse_args()
    if args.target is None:
        parser.error('Unsupported host; choose --target.')
    if args.target != native_target() and not args.build_only:
        parser.error('Cross-compilation requires --build-only.')
    if args.build_only and not args.output_dir:
        parser.error('--build-only requires --output-dir.')
    server = None
    try:
        if args.bundle:
            bundle = args.bundle.resolve(strict=True)
            handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=str(bundle.parent))
            server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), handler)
            threading.Thread(target=server.serve_forever, daemon=True).start()
            platform_url = f'http://127.0.0.1:{server.server_port}/{bundle.name}'
        else:
            platform_url = '../platform/main.roc'
        with tempfile.TemporaryDirectory(prefix='.test-', dir=ROOT) as directory:
            work = Path(directory)
            shutil.copy2(ROOT / 'tests/ParallelChecks.roc', work)
            for source in [ROOT / 'examples/map.roc', ROOT / 'tests/checks.roc']:
                app = work / source.name
                app.write_text(source.read_text().replace('../platform/main.roc', platform_url))
                executable = work / (source.stem + ('.exe' if args.target.endswith('mingw') else ''))
                subprocess.run([ROC, 'build', '--opt=speed', '--no-cache', f'--target={args.target}',
                                str(app), f'--output={executable}'], check=True)
                if args.output_dir:
                    args.output_dir.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(executable, args.output_dir / executable.name)
                if not args.build_only:
                    subprocess.run([str(executable)], check=True, timeout=65)
    finally:
        if server:
            server.shutdown()
            server.server_close()


if __name__ == '__main__':
    main()
