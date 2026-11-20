import fs from 'node:fs';
import path from 'node:path';

const manifest = JSON.parse(fs.readFileSync('data/base_tiles/manifest.json', 'utf8'));
let verified = 0;
for (const entry of manifest.templates) {
  const source = JSON.parse(fs.readFileSync(path.join('future', 'bases Minilife', entry.source), 'utf8').replace(/^\uFEFF/, ''));
  const bytes = fs.readFileSync(path.join('data', 'base_tiles', entry.packed_file));
  if (bytes.length !== entry.block_count * 3 || Object.keys(source.blocks).length !== entry.block_count) {
    throw new Error(`Count mismatch: ${entry.source}`);
  }
  const reconstructed = new Map();
  for (const [key, [offset, count]] of Object.entries(entry.chunks)) {
    const [cx, cy] = key.split(',').map(Number);
    for (let i = 0; i < count; i++) {
      const index = offset + i * 3;
      const x = cx * 16 + bytes[index];
      const y = cy * 16 + bytes[index + 1];
      const token = manifest.tokens[bytes[index + 2]];
      const tile = `${x},${y}`;
      if (reconstructed.has(tile) || source.blocks[tile] !== token) {
        throw new Error(`Tile mismatch: ${entry.source}:${tile}`);
      }
      reconstructed.set(tile, token);
    }
  }
  if (reconstructed.size !== entry.block_count) throw new Error(`Missing tiles: ${entry.source}`);
  verified += reconstructed.size;
}
console.log(`PASS: ${manifest.templates.length} bases, ${verified} tiles match source JSON`);
