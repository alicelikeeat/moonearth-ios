"""Package the verified iPhoneOS artifact, retaining executable permissions."""
import hashlib
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import zipfile

source = Path('download/build-device/Build/Products/Release-iphoneos/MoonEarth.app')
assert source.is_dir(), 'Missing verified device build'
info = plistlib.loads((source / 'Info.plist').read_bytes())
assert info['CFBundleIdentifier'] == 'com.moonearth.studio'
assert info['CFBundleShortVersionString'] == '0.1.0'
assert info['CFBundleSupportedPlatforms'] == ['iPhoneOS'], 'Never package a simulator app as IPA'
executable = info['CFBundleExecutable']
assert Path(executable).name == executable
arches = subprocess.check_output(['lipo', '-archs', str(source / executable)], text=True).split()
assert 'arm64' in arches and set(arches) <= {'arm64', 'arm64e'}, arches

payload = Path('staging/Payload')
payload.mkdir(parents=True, exist_ok=True)
app = payload / 'MoonEarth.app'
shutil.copytree(source, app, symlinks=True)
mach_magic = {bytes.fromhex(h) for h in ['feedface', 'cefaedfe', 'feedfacf', 'cffaedfe', 'cafebabe', 'bebafeca', 'cafebabf', 'bfbafeca']}
mach_files = []
for path in app.rglob('*'):
    if path.is_file() and not path.is_symlink():
        with path.open('rb') as handle:
            is_mach = handle.read(4) in mach_magic
        if is_mach:
            path.chmod(path.stat().st_mode | 0o111)
            mach_files.append(path)
            result = subprocess.run(['codesign', '-d', str(path)], capture_output=True)
            if result.returncode == 0:
                subprocess.run(['codesign', '--remove-signature', str(path)], check=True)
            assert subprocess.run(['codesign', '-d', str(path)], capture_output=True).returncode != 0
for path in app.rglob('embedded.mobileprovision'):
    path.unlink()
for path in sorted(app.rglob('_CodeSignature'), key=lambda p: len(p.parts), reverse=True):
    shutil.rmtree(path)
assert app / executable in mach_files
assert os.access(app / executable, os.X_OK)

out = Path('MoonEarth-v0.1.0-unsigned.ipa').resolve()
subprocess.run(['zip', '-qry', str(out), 'Payload'], cwd='staging', check=True)
with zipfile.ZipFile(out) as archive:
    assert archive.testzip() is None
    assert all(p.startswith('Payload/') for p in archive.namelist())
    archived = plistlib.loads(archive.read('Payload/MoonEarth.app/Info.plist'))
    assert archived['CFBundleSupportedPlatforms'] == ['iPhoneOS']
    assert archive.getinfo('Payload/MoonEarth.app/' + executable).external_attr >> 16 & 0o111
    assert not any('_CodeSignature/' in p or p.endswith('embedded.mobileprovision') for p in archive.namelist())
checksum = hashlib.sha256(out.read_bytes()).hexdigest()
Path(out.name + '.sha256').write_text(checksum + '  ' + out.name + '\n')
print(f'Validated unsigned IPA: {out.name}, {out.stat().st_size} bytes, arm64, iPhoneOS')
print(f'SHA256: {checksum}')
