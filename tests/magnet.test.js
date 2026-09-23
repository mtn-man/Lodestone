const test = require('node:test');
const assert = require('node:assert/strict');
const { parseMagnet, isValidMagnet, MagnetError } = require('../extension/lib/magnet.js');

test('parses a minimal valid magnet', () => {
  const info = parseMagnet('magnet:?xt=urn:btih:12345678');
  assert.equal(info.btih, '12345678');
  assert.equal(info.dn, '');
  assert.equal(info.trackers, 0);
});

test('parses magnet with metadata and surrounding whitespace', () => {
  const info = parseMagnet(
    '  magnet:?xt=urn:btih:45df42358b3a764e393e5dce02ab05683704a0c1&dn=test.mkv&tr=udp://a&tr=udp://b  '
  );
  assert.equal(info.btih, '45df42358b3a764e393e5dce02ab05683704a0c1');
  assert.equal(info.dn, 'test.mkv');
  assert.equal(info.trackers, 2);
});

test('rejects empty input', () => {
  assert.throws(() => parseMagnet('   '), (err) => err instanceof MagnetError && err.code === 'EMPTY');
});

test('rejects unparseable URI', () => {
  assert.throws(() => parseMagnet('://bad'), (err) => err.code === 'INVALID_URI');
});

test('rejects non-magnet scheme', () => {
  assert.throws(() => parseMagnet('https://example.com/file.torrent'), (err) => err.code === 'NOT_MAGNET');
});

test('rejects missing btih', () => {
  assert.throws(() => parseMagnet('magnet:?dn=test'), (err) => err.code === 'MISSING_BTIH');
});

test('rejects wrong xt prefix', () => {
  assert.throws(() => parseMagnet('magnet:?xt=urn:sha1:abcdefghi'), (err) => err.code === 'MISSING_BTIH');
});

test('rejects short btih', () => {
  assert.throws(() => parseMagnet('magnet:?xt=urn:btih:abc'), (err) => err.code === 'BTIH_TOO_SHORT');
});

test('isValidMagnet reports validity without throwing', () => {
  assert.equal(isValidMagnet('magnet:?xt=urn:btih:12345678'), true);
  assert.equal(isValidMagnet('https://example.com/file.torrent'), false);
  assert.equal(isValidMagnet('magnet:?xt=urn:btih:abc'), false);
});
