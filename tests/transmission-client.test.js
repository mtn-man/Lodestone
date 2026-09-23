const test = require('node:test');
const assert = require('node:assert/strict');
const {
  buildRpcUrl,
  validateTransmissionConfig,
  addMagnet,
  __resetSessionCache,
} = require('../extension/lib/transmission-client.js');

function fakeResponse({ status, sessionId = null, body = '' }) {
  return {
    status,
    headers: { get: (name) => (name === 'X-Transmission-Session-Id' ? sessionId : null) },
    text: async () => body,
    json: async () => JSON.parse(body || '{}'),
  };
}

test.beforeEach(() => {
  __resetSessionCache();
});

test('buildRpcUrl normalizes host input', () => {
  const cases = [
    ['localhost:9091', 'http://localhost:9091/transmission/rpc'],
    ['192.0.2.10:9091', 'http://192.0.2.10:9091/transmission/rpc'],
    ['localhost:9091/transmission/rpc', 'http://localhost:9091/transmission/rpc'],
    ['localhost:9091/', 'http://localhost:9091/transmission/rpc'],
    ['http://localhost:9091', 'http://localhost:9091/transmission/rpc'],
    ['https://localhost:9091', 'https://localhost:9091/transmission/rpc'],
    ['http://localhost:9091/transmission/rpc', 'http://localhost:9091/transmission/rpc'],
  ];
  for (const [host, want] of cases) {
    assert.equal(buildRpcUrl(host), want, `buildRpcUrl(${host})`);
  }
});

test('validateTransmissionConfig requires a host', () => {
  assert.throws(() => validateTransmissionConfig('', ''), /transmission host is empty/);
});

test('validateTransmissionConfig rejects auth without a colon', () => {
  assert.throws(() => validateTransmissionConfig('localhost:9091', 'tokenonly'), /user:pass/);
});

test('addMagnet performs the CSRF handshake and retries once', async () => {
  const calls = [];
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async (url, init) => {
    calls.push({ url, headers: init.headers });
    if (calls.length === 1) return fakeResponse({ status: 409, sessionId: 'abc123' });
    return fakeResponse({ status: 200, body: '{"result":"success","arguments":{}}' });
  };
  try {
    await addMagnet('magnet:?xt=urn:btih:12345678', { host: 'localhost:9091' });
  } finally {
    globalThis.fetch = originalFetch;
  }
  assert.equal(calls.length, 2);
  assert.equal(calls[0].headers['X-Transmission-Session-Id'], undefined);
  assert.equal(calls[1].headers['X-Transmission-Session-Id'], 'abc123');
});

test('addMagnet sends Basic auth on every request', async () => {
  const calls = [];
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async (url, init) => {
    calls.push(init.headers);
    if (calls.length === 1) return fakeResponse({ status: 409, sessionId: 's1' });
    return fakeResponse({ status: 200, body: '{"result":"success","arguments":{}}' });
  };
  try {
    await addMagnet('magnet:?xt=urn:btih:12345678', { host: 'localhost:9091', auth: 'user:pass' });
  } finally {
    globalThis.fetch = originalFetch;
  }
  const expected = `Basic ${Buffer.from('user:pass').toString('base64')}`;
  assert.equal(calls[0].Authorization, expected);
  assert.equal(calls[1].Authorization, expected);
});

test('addMagnet propagates an RPC-level error result', async () => {
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async () => fakeResponse({ status: 200, body: '{"result":"something went wrong"}' });
  try {
    await assert.rejects(
      addMagnet('magnet:?xt=urn:btih:12345678', { host: 'localhost:9091' }),
      /something went wrong/
    );
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test('addMagnet wraps a non-200 status with the response body', async () => {
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async () => fakeResponse({ status: 500, body: 'boom' });
  try {
    await assert.rejects(
      addMagnet('magnet:?xt=urn:btih:12345678', { host: 'localhost:9091' }),
      /unexpected status 500: boom/
    );
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test('addMagnet rejects when host is missing', async () => {
  await assert.rejects(
    addMagnet('magnet:?xt=urn:btih:12345678', { host: '' }),
    /transmission host is empty/
  );
});
