import { test } from 'node:test';
import assert from 'node:assert/strict';
import { computeStatus, formatStatus } from '../src/status.js';

test('computes remaining and percent for normal usage', () => {
  const s = computeStatus({ used: 100, size: 1000, model: 'hy3' });
  assert.equal(s.token.remaining, 900);
  assert.equal(s.token.percent, 10);
  assert.equal(s.model, 'hy3');
});

test('clamps percent to 100 when used exceeds size', () => {
  const s = computeStatus({ used: 1200, size: 1000, model: 'x' });
  assert.equal(s.token.remaining, 0);
  assert.equal(s.token.percent, 100);
});

test('handles size 0 without producing NaN', () => {
  const s = computeStatus({ used: 0, size: 0, model: 'x' });
  assert.equal(s.token.percent, null);
  assert.equal(s.token.remaining, null);
});

test('defaults model to unknown when missing', () => {
  const s = computeStatus({});
  assert.equal(s.model, 'unknown');
});

test('parses credit_json when present', () => {
  const s = computeStatus({ used: 1, size: 2, model: 'x', credit_json: '{"a":1}' });
  assert.deepEqual(s.credit, { a: 1 });
});

test('ignores malformed credit_json', () => {
  const s = computeStatus({ used: 1, size: 2, model: 'x', credit_json: 'not json' });
  assert.equal(s.credit, null);
});

test('formatStatus renders a readable string', () => {
  const out = formatStatus(computeStatus({ used: 100, size: 1000, model: 'hy3', title: 't' }));
  assert.match(out, /model=hy3/);
  assert.match(out, /10%/);
});
