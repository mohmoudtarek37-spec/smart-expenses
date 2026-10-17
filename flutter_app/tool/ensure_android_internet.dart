// ignore_for_file: prefer_interpolation_to_compose_strings
import 'dart:io';

/// Prepare generated Android manifests for cloud auth, password reset and
/// Google OAuth. Run immediately after flutter create (CI does this too).
void main() {
  final manifest = File('android/app/src/main/AndroidManifest.xml');
  if (!manifest.existsSync()) {
    stderr.writeln('Missing Android manifest; run flutter create first.');
    exitCode = 1;
    return;
  }
  var source = manifest.readAsStringSync();
  if (!source.contains('android.permission.INTERNET')) {
    final root = RegExp(r'<manifest\b[^>]*>');
    if (!root.hasMatch(source)) {
      stderr.writeln('Unexpected Android manifest root.');
      exitCode = 1;
      return;
    }
    source = source.replaceFirstMapped(root, (m) =>
        (m.group(0) ?? '') + '\n'
        '    <uses-permission android:name="android.permission.INTERNET" />');
  }

  const scheme = 'io.github.mohmoudtarek37spec.hesabaty';
  if (!source.contains('android:scheme="' + scheme + '"')) {
    final activity = RegExp(
        r'<activity\b[^>]*android:name="\.MainActivity"[^>]*>');
    if (!activity.hasMatch(source)) {
      stderr.writeln('MainActivity not found, cannot install callback.');
      exitCode = 1;
      return;
    }
    const filter = '''
        <intent-filter android:autoVerify="false">
            <action android:name="android.intent.action.VIEW" />
            <category android:name="android.intent.category.DEFAULT" />
            <category android:name="android.intent.category.BROWSABLE" />
            <data android:scheme="io.github.mohmoudtarek37spec.hesabaty"
                  android:host="auth-callback" />
        </intent-filter>
''';
    source = source.replaceFirstMapped(activity,
        (m) => (m.group(0) ?? '') + '\n' + filter);
  }
  manifest.writeAsStringSync(source);
  stdout.writeln('Android INTERNET permission and OAuth callback verified.');
}
