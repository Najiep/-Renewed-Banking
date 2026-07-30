import { cp, mkdir, readFile, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
const root = resolve(import.meta.dirname, '..');
await mkdir(resolve(root, 'dist/assets'), { recursive: true });
const source = await readFile(resolve(root, 'src/main.ts'), 'utf8');
await writeFile(resolve(root, 'dist/assets/app.js'), source);
await cp(resolve(root, 'src/styles.css'), resolve(root, 'dist/assets/app.css'));
await cp(resolve(root, 'src/index.html'), resolve(root, 'dist/index.html'));
console.log('Renewed Banking UI built.');
