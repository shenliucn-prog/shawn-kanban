import { test } from 'node:test';
import assert from 'node:assert/strict';
import { shouldUpload } from '../src/report-policy.js';
const snapshot = { ts: 1000, quotas: { codex: { ok: true, remaining: 100 } } };
test('unchanged usage still sends heartbeat', () => {
  assert.equal(shouldUpload(snapshot, snapshot, 2000), false);
  assert.equal(shouldUpload(snapshot, snapshot, 301000), true);
});
test('failure keeps retry eligible against the same successful upload', () => {
  const next = { ts: 2000, quotas: { codex: { ok: true, remaining: 50 } } };
  assert.equal(shouldUpload(snapshot, next, 2000), true);
  assert.equal(shouldUpload(snapshot, next, 3000), true);
  assert.equal(shouldUpload(next, next, 3000), false);
});
test('first report and recovered provider are uploaded', () => {
  assert.equal(shouldUpload(null, snapshot, 2000), true);
  assert.equal(shouldUpload({ ...snapshot, quotas: {} }, snapshot, 2000), true);
});
