// ignore_for_file: prefer_interpolation_to_compose_strings
import 'dart:io';

/// Configures Flutter-generated Gradle Kotlin DSL for a real release signing
/// key. Uses GitHub Actions environment secrets, never hardcoded credentials.
void main() {
  final gradle = File('android/app/build.gradle.kts');
  if (!gradle.existsSync()) {
    stderr.writeln('Missing Kotlin DSL app Gradle file.');
    exitCode = 1;
    return;
  }
  var text = gradle.readAsStringSync();
  const debugLine = 'signingConfig = signingConfigs.getByName("debug")';
  if (!text.contains(debugLine) || !text.contains('    buildTypes {')) {
    stderr.writeln('Unexpected Gradle release template; aborting unsigned release.');
    exitCode = 1;
    return;
  }
  const config = '''
    signingConfigs {
        create("release") {
            storeFile = file("release-key.jks")
            storePassword = System.getenv("ANDROID_KEYSTORE_PASSWORD")
            keyAlias = System.getenv("ANDROID_KEY_ALIAS")
            keyPassword = System.getenv("ANDROID_KEY_PASSWORD")
        }
    }
''';
  text = text.replaceFirst('    buildTypes {', config + '    buildTypes {');
  text = text.replaceFirst(
    debugLine, 'signingConfig = signingConfigs.getByName("release")');
  gradle.writeAsStringSync(text);
  stdout.writeln('Release signing configured from environment secrets.');
}
