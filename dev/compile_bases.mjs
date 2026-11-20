import fs from 'node:fs';
import path from 'node:path';

const root = path.join('future', 'bases Minilife');
const output = path.join('data', 'base_tiles');
const assignment = JSON.parse(fs.readFileSync('data/base_assignment.json', 'utf8'));
const tokens = [
  'brick', 'dirt', 'door', 'grass', 'pillar', 'stone_floor', 'stone_wall',
  'water', 'wheat', 'wood_floor', 'wood_wall',
];
fs.mkdirSync(output, {recursive: true});
const manifest = {schema_version: 1, chunk_size: 16, tokens, templates: []};

for (const [index, entry] of assignment.templates.entries()) {
  const raw = fs.readFileSync(path.join(root, entry.file), 'utf8').replace(/^\uFEFF/, '');
  const source = JSON.parse(raw);
  if (source.format !== 'pixel_architect_v1' || source.map_size?.[0] !== 1000 || source.map_size?.[1] !== 1000) {
    throw new Error(`Invalid base format: ${entry.file}`);
  }
  const chunks = new Map();
  const bounds = [1000, 1000, -1, -1];
  for (const [key, token] of Object.entries(source.blocks)) {
    const [x, y] = key.split(',').map(Number);
    const tokenId = tokens.indexOf(token);
    if (!Number.isInteger(x) || !Number.isInteger(y) || x < 0 || y < 0 || x >= 1000 || y >= 1000 || tokenId < 0) {
      throw new Error(`Invalid block ${entry.file}:${key}=${token}`);
    }
    const chunkKey = `${Math.floor(x / 16)},${Math.floor(y / 16)}`;
    if (!chunks.has(chunkKey)) chunks.set(chunkKey, []);
    chunks.get(chunkKey).push([x % 16, y % 16, tokenId]);
    bounds[0] = Math.min(bounds[0], x);
    bounds[1] = Math.min(bounds[1], y);
    bounds[2] = Math.max(bounds[2], x);
    bounds[3] = Math.max(bounds[3], y);
  }
  if (Object.keys(source.blocks).length !== source.total_blocks) {
    throw new Error(`Count mismatch: ${entry.file}`);
  }
  const packedFile = `${String(index).padStart(2, '0')}.mbase`;
  const buffer = Buffer.alloc(source.total_blocks * 3);
  const chunkIndex = {};
  let offset = 0;
  const keys = [...chunks.keys()].sort((a, b) => {
    const [ax, ay] = a.split(',').map(Number);
    const [bx, by] = b.split(',').map(Number);
    return ay - by || ax - bx;
  });
  for (const key of keys) {
    const records = chunks.get(key);
    records.sort((a, b) => a[1] - b[1] || a[0] - b[0]);
    chunkIndex[key] = [offset, records.length];
    for (const record of records) {
      for (const value of record) buffer[offset++] = value;
    }
  }
  fs.writeFileSync(path.join(output, packedFile), buffer);
  manifest.templates.push({source: entry.file, packed_file: packedFile, block_count: source.total_blocks, bounds, chunks: chunkIndex});
}
fs.writeFileSync(path.join(output, 'manifest.json'), JSON.stringify(manifest));
console.log(`Compiled ${manifest.templates.length} bases, ${manifest.templates.reduce((n, x) => n + x.block_count, 0)} tiles`);
