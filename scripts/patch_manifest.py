from pathlib import Path
p = Path('android/app/src/main/AndroidManifest.xml')
s = p.read_text(encoding='utf-8')
if 'android.permission.INTERNET' not in s:
    s = s.replace('<manifest xmlns:android="http://schemas.android.com/apk/res/android">',
        '<manifest xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <uses-permission android:name="android.permission.INTERNET"/>\n'
        '    <uses-permission android:name="android.permission.RECORD_AUDIO"/>\n'
        '    <queries>\n'
        '      <intent><action android:name="android.speech.RecognitionService" /></intent>\n'
        '      <intent><action android:name="android.intent.action.TTS_SERVICE" /></intent>\n'
        '    </queries>')
# Name and no cleartext HTTP backend
s = s.replace('android:label="murtadha_ai"', 'android:label="Murtadha AI"')
p.write_text(s, encoding='utf-8')
print('Patched', p)
