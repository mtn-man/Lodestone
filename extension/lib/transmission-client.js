(function (root) {
  'use strict';

  let cachedSessionId = '';
  const DEFAULT_TIMEOUT_MS = 10000;

  function buildHostUrl(hostInput, path) {
    const host = (hostInput ?? '').trim();
    const raw = host.includes('://') ? host : `http://${host}`;
    try {
      const u = new URL(raw);
      if (!u.host) throw new Error('empty host');
      const scheme = u.protocol || 'http:';
      return `${scheme}//${u.host}${path}`;
    } catch {
      return `http://${host}${path}`;
    }
  }

  function buildRpcUrl(hostInput) {
    return buildHostUrl(hostInput, '/transmission/rpc');
  }

  function buildWebUrl(hostInput) {
    return buildHostUrl(hostInput, '/transmission/web/');
  }

  function validateTransmissionConfig(host, auth) {
    if (!(host ?? '').trim()) {
      throw new Error('transmission host is empty');
    }
    const trimmedAuth = (auth ?? '').trim();
    if (trimmedAuth && !trimmedAuth.includes(':')) {
      throw new Error('transmission auth must be in "user:pass" form');
    }
  }

  async function rpcCall(method, args, { host, auth, signal }) {
    const url = buildRpcUrl(host);
    const body = JSON.stringify({ method, arguments: args });
    const authHeader = (auth ?? '').trim() ? `Basic ${btoa(auth.trim())}` : null;

    const doFetch = (sessionId) =>
      fetch(url, {
        method: 'POST',
        signal,
        headers: {
          'Content-Type': 'application/json',
          ...(sessionId ? { 'X-Transmission-Session-Id': sessionId } : {}),
          ...(authHeader ? { Authorization: authHeader } : {}),
        },
        body,
      });

    let resp = await doFetch(cachedSessionId);
    if (resp.status === 409) {
      cachedSessionId = resp.headers.get('X-Transmission-Session-Id') || '';
      resp = await doFetch(cachedSessionId);
    }

    if (resp.status !== 200) {
      const text = (await resp.text()).trim();
      throw new Error(`transmission rpc: unexpected status ${resp.status}: ${text}`);
    }

    const data = await resp.json();
    if (data.result !== 'success') {
      throw new Error(`transmission rpc ${method}: ${data.result}`);
    }
    return data.arguments;
  }

  async function addMagnet(uri, { host, auth, timeoutMs = DEFAULT_TIMEOUT_MS } = {}) {
    validateTransmissionConfig(host, auth);
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeoutMs);
    try {
      await rpcCall('torrent-add', { filename: uri }, { host, auth, signal: controller.signal });
    } catch (err) {
      throw new Error(`transmission add failed (host=${host}): ${err.message}`);
    } finally {
      clearTimeout(timer);
    }
  }

  // Idempotent RPC call used purely to confirm the host is reachable and,
  // if auth is set, that it's accepted -- used to validate a host before
  // it's saved, so a dormant/wrong IP is rejected up front instead of
  // failing silently the next time a magnet link is clicked.
  async function testConnection(host, auth, { timeoutMs = DEFAULT_TIMEOUT_MS } = {}) {
    validateTransmissionConfig(host, auth);
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeoutMs);
    try {
      await rpcCall('session-get', {}, { host, auth, signal: controller.signal });
    } catch (err) {
      if (err.name === 'AbortError') {
        throw new Error(`could not reach transmission at ${host}: timed out -- try a different address`);
      }
      throw new Error(`could not reach transmission at ${host}: ${err.message}`);
    } finally {
      clearTimeout(timer);
    }
  }

  function __resetSessionCache() {
    cachedSessionId = '';
  }

  const api = {
    buildRpcUrl,
    buildWebUrl,
    validateTransmissionConfig,
    addMagnet,
    testConnection,
    __resetSessionCache,
  };

  if (typeof module !== 'undefined' && module.exports) {
    module.exports = api;
  } else {
    root.Lodestone = Object.assign(root.Lodestone || {}, api);
  }
})(typeof self !== 'undefined' ? self : globalThis);
