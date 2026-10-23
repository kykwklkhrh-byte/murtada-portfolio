from pathlib import Path
import re

manifest = Path('android/app/src/main/AndroidManifest.xml')
if not manifest.exists():
    raise SystemExit('Android platform files are missing. Run flutter create first.')
text = manifest.read_text(encoding='utf-8')
permissions = [
    '<uses-permission android:name="android.permission.INTERNET" />',
    '<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />',
    # Android all-files access is optional; requested only from advanced screens.
    '<uses-permission android:name="android.permission.MANAGE_EXTERNAL_STORAGE" />',
]
for permission in permissions:
    if f'android:name="{re.search(r"android:name=\"([^\"]+)\"", permission).group(1)}"' not in text:
        text = text.replace('<application', '    ' + permission + '\n    <application', 1)
text = re.sub(r'android:label="[^"]*"', 'android:label="مرتضى ستار"', text, count=1)
manifest.write_text(text, encoding='utf-8')
for gradle in Path('android/app').glob('build.gradle*'):
    content = gradle.read_text(encoding='utf-8')
    content = content.replace('minSdk = flutter.minSdkVersion', 'minSdk = 23').replace('minSdkVersion flutter.minSdkVersion', 'minSdkVersion 23')
    gradle.write_text(content, encoding='utf-8')
print('Android label, network and optional file access permissions configured.')
