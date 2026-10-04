import { mkdir, copyFile, readdir } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const dependencies = path.join(root, 'tools/ocr-runtime/node_modules');
const output = path.join(root, 'web/ocr');
await mkdir(path.join(output, 'core'), { recursive: true });
for (const file of ['tesseract.min.js', 'worker.min.js']) {
  await copyFile(path.join(dependencies, 'tesseract.js/dist', file), path.join(output, file));
}
await copyFile(path.join(dependencies, 'tesseract.js/LICENSE.md'), path.join(output, 'LICENSE-tesseract.txt'));
await copyFile(path.join(dependencies, 'tesseract.js-core/LICENSE'), path.join(output, 'LICENSE-core.txt'));
for (const file of await readdir(path.join(dependencies, 'tesseract.js-core'))) {
  if (/\.wasm(?:\.js)?$/.test(file)) {
    await copyFile(path.join(dependencies, 'tesseract.js-core', file), path.join(output, 'core', file));
  }
}
console.log('Lokale OCR-Laufzeit nach web/ocr kopiert.');
