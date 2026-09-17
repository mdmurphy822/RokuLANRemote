import hashlib, struct, zipfile
from pathlib import Path
import importlib.util

ROOT = Path(__file__).resolve().parents[1]
DIST = ROOT / 'dist'
VERSION = '0.2.0'


def app_bootstrap_command():
    ps = (
        "$x=$env:RLR_SELF_EXE;"
        "$a=[IO.File]::ReadAllBytes($x);"
        "if([Text.Encoding]::ASCII.GetString($a,$a.Length-16,8) -ne 'RLRPS001'){exit};"
        "$n=[BitConverter]::ToInt64($a,$a.Length-8);"
        "$s=$a.Length-16-$n;"
        "$b=New-Object byte[] ([int]$n);"
        "[Array]::Copy($a,$s,$b,0,[int]$n);"
        "$p=[IO.Path]::Combine([IO.Path]::GetTempPath(),'RokuLANRemote-'+[Guid]::NewGuid().ToString('N')+'.ps1');"
        "[IO.File]::WriteAllBytes($p,$b);"
        "& $p;"
        "Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue"
    )
    return 'powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -Command "' + ps + '"'


def package_bootstrap_command():
    ps = (
        "$x=$env:RLR_SELF_EXE;"
        "$a=[IO.File]::ReadAllBytes($x);"
        "if([Text.Encoding]::ASCII.GetString($a,$a.Length-24,8) -ne 'RLRPKG01'){exit};"
        "$n=[BitConverter]::ToInt64($a,$a.Length-8);"
        "$s=$a.Length-24-$n;"
        "$b=New-Object byte[] ([int]$n);"
        "[Array]::Copy($a,$s,$b,0,[int]$n);"
        "$p=[IO.Path]::Combine([IO.Path]::GetTempPath(),'RokuLANRemote-Package-'+[Guid]::NewGuid().ToString('N')+'.ps1');"
        "[IO.File]::WriteAllBytes($p,$b);"
        "& $p;"
        "Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue"
    )
    return 'powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -Command "' + ps + '"'


spec = importlib.util.spec_from_file_location('pegen', ROOT / 'build' / 'make_winexec_pe.py')
pegen = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pegen)
DIST.mkdir(exist_ok=True)

app_ps = (ROOT / 'src' / 'RokuLanRemote.ps1').read_bytes()
app_exe = DIST / 'RokuLANRemote.exe'
pegen.make_pe(app_bootstrap_command(), str(app_exe), True)
with app_exe.open('ab') as f:
    f.write(app_ps)
    f.write(b'RLRPS001')
    f.write(struct.pack('<Q', len(app_ps)))
app_bytes = app_exe.read_bytes()
app_sha = hashlib.sha256(app_bytes).hexdigest()

inst_text = (ROOT / 'installer' / 'Installer.ps1').read_text(encoding='utf-8')
inst_text = inst_text.replace('__APP_VERSION__', VERSION).replace('__APP_SHA256__', app_sha)
resolved_inst = ROOT / 'installer' / 'Installer.resolved.ps1'
resolved_inst.write_text(inst_text, encoding='utf-8-sig')
inst_bytes = resolved_inst.read_bytes()
package_exe = DIST / f'RokuLANRemote-Package-{VERSION}.exe'
pegen.make_pe(package_bootstrap_command(), str(package_exe), True)
with package_exe.open('ab') as f:
    f.write(app_bytes)
    f.write(inst_bytes)
    f.write(b'RLRPKG01')
    f.write(struct.pack('<Q', len(app_bytes)))
    f.write(struct.pack('<Q', len(inst_bytes)))

hashes = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in [app_exe, package_exe]}
(DIST / 'SHA256SUMS.txt').write_text(
    ''.join(f'{h}  {n}\n' for n, h in hashes.items()), encoding='ascii'
)

portable_zip = DIST / f'RokuLANRemote-{VERSION}-portable.zip'
with zipfile.ZipFile(portable_zip, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as z:
    z.write(app_exe, 'RokuLANRemote.exe')
    z.write(DIST / 'SHA256SUMS.txt', 'SHA256SUMS.txt')
    for n in ['README.md', 'LICENSE', 'CHANGELOG.md']:
        if (ROOT / n).exists():
            z.write(ROOT / n, n)

source_zip = DIST / f'RokuLANRemote-{VERSION}-source.zip'
with zipfile.ZipFile(source_zip, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as z:
    for p in ROOT.rglob('*'):
        if not p.is_file():
            continue
        rel = p.relative_to(ROOT)
        if rel.parts[0] in {'dist', '.git'}:
            continue
        if rel.as_posix() == 'installer/Installer.resolved.ps1' or '__pycache__' in rel.parts:
            continue
        z.write(p, rel.as_posix())

release_zip = DIST / f'RokuLANRemote-{VERSION}-release.zip'
with zipfile.ZipFile(release_zip, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as z:
    z.write(app_exe, 'RokuLANRemote.exe')
    z.write(package_exe, package_exe.name)
    z.write(DIST / 'SHA256SUMS.txt', 'SHA256SUMS.txt')
    for n in ['README.md', 'LICENSE', 'CHANGELOG.md', 'SECURITY.md']:
        if (ROOT / n).exists():
            z.write(ROOT / n, n)

print('app bootstrap chars:', len(app_bootstrap_command()))
print('package bootstrap chars:', len(package_bootstrap_command()))
for p in [app_exe, package_exe, portable_zip, source_zip, release_zip, DIST / 'SHA256SUMS.txt']:
    print(p.name, p.stat().st_size, hashlib.sha256(p.read_bytes()).hexdigest())
