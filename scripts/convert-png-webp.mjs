// One-off: convert large bundled PNGs to WebP q82.
// - Pro paywall hero carousel (assets/pro/hero_*.png)
// - Onboarding step illustrations (assets/onboarding/step*.png)
// Skips launcher icons (Android adaptive icons require PNG).

import sharp from 'sharp';
import fs from 'node:fs';
import path from 'node:path';

const root = path.resolve(path.dirname(new URL(import.meta.url).pathname.replace(/^\//, '')), '..');

const targets = [
  'assets/pro/hero_1.png',
  'assets/pro/hero_2.png',
  'assets/pro/hero_3.png',
  'assets/pro/hero_4.png',
  'assets/onboarding/step1.png',
  'assets/onboarding/step2.png',
  'assets/onboarding/step3.png',
];

let totalBefore = 0;
let totalAfter = 0;
const results = [];

for (const rel of targets) {
  const input = path.join(root, rel);
  const output = input.replace(/\.png$/i, '.webp');

  if (!fs.existsSync(input)) {
    console.log(`[skip] ${rel} (not found)`);
    continue;
  }

  const beforeBytes = fs.statSync(input).size;

  try {
    await sharp(input).webp({ quality: 82 }).toFile(output);
  } catch (err) {
    console.error(`[fail] ${rel}: ${err.message}`);
    continue;
  }

  if (!fs.existsSync(output) || fs.statSync(output).size === 0) {
    console.error(`[fail] ${rel}: output missing or empty`);
    continue;
  }

  const afterBytes = fs.statSync(output).size;
  fs.unlinkSync(input);

  totalBefore += beforeBytes;
  totalAfter += afterBytes;
  const savedKb = ((beforeBytes - afterBytes) / 1024).toFixed(1);
  const pct = (((beforeBytes - afterBytes) / beforeBytes) * 100).toFixed(1);
  console.log(
    `[ok] ${rel}  ${(beforeBytes / 1024).toFixed(0)}KB -> ${(afterBytes / 1024).toFixed(0)}KB  (-${savedKb}KB, -${pct}%)`
  );
  results.push({ rel, beforeBytes, afterBytes });
}

const totalSavedKb = ((totalBefore - totalAfter) / 1024).toFixed(1);
const totalPct = totalBefore ? (((totalBefore - totalAfter) / totalBefore) * 100).toFixed(1) : '0';
console.log('---');
console.log(
  `TOTAL: ${(totalBefore / 1024).toFixed(0)}KB -> ${(totalAfter / 1024).toFixed(0)}KB  (saved ${totalSavedKb}KB, -${totalPct}%)`
);
