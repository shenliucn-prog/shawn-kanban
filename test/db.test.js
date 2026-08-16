import { test } from 'node:test';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { openDb, readStatus } from '../src/db.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
const FIXTURE = join(__dirname, 'fixtures', 'workbuddy.db');
const EMPTY = join(__dirname, 'fixtures', 'empty.db');

test('reads status from fixture DB (newest session with usage)', () => {
  const db = openDb(FIXTURE);
  try {
    const s = readStatus(db);
    assert.equal(s.model, 'hy3');
    assert.equal(s.token.used, 100);
    assert.equal(s.token.size, 1000);
    assert.equal(s.token.remaining, 900);
    assert.equal(s.token.percent, 10);
    assert.equal(s.source, 'session');
  } finally {
    db.close();
  }
});

test('falls back to latest usage when the scoped session has none', () => {
  const db = openDb(FIXTURE);
  try {
    const s = readStatus(db, { cwdFilter: 'C:\\other\\path' });
    // s3 is the only session in that cwd and has no usage -> fallback to newest usage (s2)
    assert.equal(s.source, 'fallback');
    assert.equal(s.token.size, 1000);
    assert.equal(s.token.used, 100);
  } finally {
    db.close();
  }
});

test('returns empty-source status when no sessions exist', () => {
  const db = openDb(EMPTY);
  try {
    const s = readStatus(db);
    assert.equal(s.source, 'empty');
    assert.equal(s.model, 'unknown');
    assert.equal(s.token.remaining, null);
  } finally {
    db.close();
  }
});
