#!/usr/bin/env python3
"""Build and run the example and ownership checks, optionally through a bundle URL."""
import argparse
import functools
import http.server
import json
import os
import shutil
import subprocess
import tempfile
import threading
from pathlib import Path

from common import ROOT, ROC, TARGETS, native_target


def check_cli(executable):
    environment = {**os.environ, 'ROC_PARALLEL_DIAGNOSTICS': '1'}

    def run(arguments, expected_status):
        result = subprocess.run([str(executable), *arguments], capture_output=True,
                                text=True, encoding='utf-8', env=environment, timeout=65)
        if result.returncode != expected_status:
            raise AssertionError(f'{arguments}: expected status {expected_status}, got {result.returncode}: {result.stderr}')
        assert result.stdout == '', result.stdout
        lines = result.stderr.splitlines(keepends=True)
        assert lines and 'all Roc allocations released.' in lines[-1], result.stderr
        return ''.join(lines[:-1])

    assert run([], 0) == ''
    assert json.loads(run(['args'], 0)) == []
    values = ['', 'a b', 'quote"inside', 'C:\\path\\', 'é本🙂', 'x' * 400]
    assert json.loads(run(['args', *values], 0)) == values
    assert run(['exit-zero'], 0) == ''
    assert run(['exit-positive'], 7) == ''
    assert run(['exit-negative'], 0xffffffff if os.name == 'nt' else 255) == ''
    assert run(['error'], 1) == 'Program exited with error: Problem("' + 'error details ' * 8 + '")\n'
    assert run(['stderr'], 0) == ('a long message ' * 8 + '\n') * 2
    invalid = '\ud800' if os.name == 'nt' else os.fsdecode(b'\xff')
    assert run([invalid], 2) == 'Command-line arguments must be valid Unicode\n'
    quiet_env = {key: value for key, value in os.environ.items() if key != 'ROC_PARALLEL_DIAGNOSTICS'}
    quiet = subprocess.run([str(executable)], capture_output=True, env=quiet_env, timeout=65)
    assert quiet.returncode == 0 and quiet.stdout == b'' and quiet.stderr == b''
    print('Command-line arguments, exit codes, errors, stderr, and cleanup passed.')


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
            for source in [ROOT / 'examples/map.roc', ROOT / 'tests/checks.roc', ROOT / 'tests/cli.roc']:
                app = work / source.name
                app.write_text(source.read_text().replace('../platform/main.roc', platform_url))
                executable = work / (source.stem + ('.exe' if args.target.endswith('mingw') else ''))
                subprocess.run([ROC, 'build', '--opt=speed', '--no-cache', f'--target={args.target}',
                                str(app), f'--output={executable}'], check=True)
                if args.output_dir:
                    args.output_dir.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(executable, args.output_dir / executable.name)
                if not args.build_only:
                    if source.stem == 'cli':
                        check_cli(executable)
                    else:
                        subprocess.run([str(executable)], check=True, timeout=65,
                                       env={**os.environ, 'ROC_PARALLEL_DIAGNOSTICS': '1'})
    finally:
        if server:
            server.shutdown()
            server.server_close()


if __name__ == '__main__':
    main()
