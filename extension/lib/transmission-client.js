(function (root) {
  'use strict';

  let cachedSessionId = '';

  function buildRpcUrl(hostInput) {
    const host = (hostInput ?? '').trim();
    const raw = host.includes('://') ? host : `http://${host}`;
    try {
      const u = new URL(raw);
      if (!u.host) throw new Error('empty host');
      const scheme = u.protocol || 'http:';
      return `${scheme}//${u.host}/transmission/rpc`;
    } catch {
      return `http://${host}/transmission/rpc`;
    }
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

  async function addMagnet(uri, { host, auth, timeoutMs = 10000 } = {}) {
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

  function __resetSessionCache() {
    cachedSessionId = '';
  }

  const api = { buildRpcUrl, validateTransmissionConfig, addMagnet, __resetSessionCache };

  if (typeof module !== 'undefined' && module.exports) {
    module.exports = api;
  } else {
    root.Lodestone = Object.assign(root.Lodestone || {}, api);
  }
})(typeof self !== 'undefined' ? self : globalThis);
