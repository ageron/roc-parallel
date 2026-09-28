import ast
import os
import platform
import re
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
ROC = os.environ.get("ROC", "roc")

TARGETS = {
    'arm64mac': 'aarch64-macos', 'x64mac': 'x86_64-macos',
    'arm64musl': 'aarch64-linux-musl', 'x64musl': 'x86_64-linux-musl',
    'arm64mingw': 'aarch64-windows-gnu', 'x64mingw': 'x86_64-windows-gnu',
}


def native_target():
    arch = {'arm64': 'arm64', 'aarch64': 'arm64', 'x86_64': 'x64', 'amd64': 'x64'}.get(platform.machine().lower())
    system = {'Darwin': 'mac', 'Linux': 'musl', 'Windows': 'mingw'}.get(platform.system())
    return arch + system if arch and system else None


def install_runtime(work, output, target):
    # Let Zig build its target CRT/libc, then copy exactly the runtime files
    # from its link command. This avoids a system C compiler or Windows SDK.
    if target.endswith('mac'):
        return []
    probe = work / 'runtime_probe.c'
    probe.write_text('int main(void) { return 0; }\n')
    environment = subprocess.check_output(['zig', 'env'], encoding='utf-8')
    cache_match = re.search(r'\.global_cache_dir = ("(?:\\.|[^"])*")', environment)
    if not cache_match:
        raise RuntimeError('Could not find Zig 0.16.0 cache directory.')
    # Zig env emits ZON byte escapes (including \xNN for UTF-8 paths).
    cache = Path(ast.literal_eval("b" + cache_match.group(1)).decode("utf-8"))
    command = ['zig', 'build-exe', str(probe), '-target', TARGETS[target], '-lc', '-O', 'ReleaseSafe',
               f'-femit-bin={work / "runtime-probe.exe"}', '--global-cache-dir', str(cache), '--verbose-link']
    result = subprocess.run(command, encoding="utf-8", capture_output=True)
    if result.returncode:
        raise RuntimeError(result.stderr)
    lines = [line for line in result.stderr.splitlines() if line.startswith(('ld.lld ', 'lld-link '))]
    if not lines:
        raise RuntimeError('Could not find the Zig 0.16.0 runtime link command.')
    files = []
    # Zig prints unquoted paths. Match the known cache prefix rather than
    # splitting on spaces (Windows user profiles often contain spaces).
    pattern = re.escape(str(cache)) + r'[\\/]o[\\/][0-9a-f]+[\\/][\w.-]+\.(?:obj|o|a|lib)'
    for filename in re.findall(pattern, lines[-1]):
        path = Path(filename)
        if path.suffix in ('.o', '.obj', '.a', '.lib') and path.is_file() and path.stem != 'runtime_probe':
            shutil.copy2(path, output / path.name)
            files.append(path.name)
    if not files:
        raise RuntimeError('Zig did not provide target runtime files.')
    return files

