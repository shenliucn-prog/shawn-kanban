import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { once } from 'node:events';
import { createServer } from '../src/server.js';

test('manifest identifies retrievable image bytes and selected language', async () => {
  const png = Buffer.alloc(33);
  png.writeUInt32BE(1072, 16); png.writeUInt32BE(1448, 20);
  let selected;
  const server = createServer({renderImage: async language => { selected = language; return png; }});
  server.listen(0, '127.0.0.1'); await once(server, 'listening');
  try {
    const base = 'http://127.0.0.1:' + server.address().port;
    const manifest = await (await fetch(base + '/api/display?lang=en')).json();
    assert.equal(selected, 'en'); assert.equal(manifest.schemaVersion, 1);
    assert.equal(manifest.width, 1072); assert.equal(manifest.height, 1448);
    assert.equal(manifest.sha256, createHash('sha256').update(png).digest('hex'));
    assert.deepEqual(Buffer.from(await (await fetch(base + manifest.image_url)).arrayBuffer()), png);
    assert.equal((await fetch(base + '/api/image/not-present.png')).status, 404);
  } finally { server.closeAllConnections(); await new Promise(resolve => server.close(resolve)); }
});

test('failed renderer returns unavailable instead of a successful manifest', async () => {
  const server = createServer({renderImage: async () => { throw new Error('offline'); }});
  server.listen(0, '127.0.0.1'); await once(server, 'listening');
  try { assert.equal((await fetch('http://127.0.0.1:' + server.address().port + '/api/display')).status, 503); }
  finally { server.closeAllConnections(); await new Promise(resolve => server.close(resolve)); }
});
