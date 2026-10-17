import 'dart:io';

/// flutter create generates platform sources in CI. INTERNET is automatically
/// present in debug manifests but MUST also be in the main/release manifest,
/// otherwise login and cloud sync break when the app is distributed.
void main() {
  final manifest = File('android/app/src/main/AndroidManifest.xml');
  if (!manifest.existsSync()) {
    stderr.writeln('Android manifest missing. Run flutter create first.');
    exitCode = 1;
    return;
  }
  final content = manifest.readAsStringSync();
  if (content.contains('android.permission.INTERNET')) {
    stdout.writeln('Main Android manifest already allows internet.');
    return;
  }
  final pattern = RegExp(r'<manifest\b[^>]*>');
  if (!pattern.hasMatch(content)) {
    stderr.writeln('Unrecognized Android manifest; no file was changed.');
    exitCode = 1;
    return;
  }
  final updated = content.replaceFirstMapped(
    pattern,
    (match) => '${match.group(0)}\n'
        '    <uses-permission android:name="android.permission.INTERNET" />',
  );
  manifest.writeAsStringSync(updated);
  stdout.writeln('Added INTERNET permission to Android main manifest.');
}
