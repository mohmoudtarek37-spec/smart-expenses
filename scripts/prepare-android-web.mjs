import { cp, mkdir, rm } from 'node:fs/promises';

// Keep the website root unchanged for GitHub Pages. Only stage assets for Capacitor.
const files = [
  'index.html', 'styles.css', 'app.js', 'ui.js', 'i18n.js',
  'theme.js', 'report.js', 'sw.js', 'manifest.webmanifest'
];

await rm('www', { recursive: true, force: true });
await mkdir('www', { recursive: true });
for (const file of files) {
  await cp(file, `www/${file}`);
}
await cp('icons', 'www/icons', { recursive: true });
console.log('Prepared web assets for Hesabaty Android preview.');
