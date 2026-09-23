(function (root) {
  'use strict';

  const BTIH_PREFIX = 'urn:btih:';
  const MIN_BTIH_LEN = 8;

  class MagnetError extends Error {
    constructor(code, message) {
      super(message);
      this.name = 'MagnetError';
      this.code = code; // 'EMPTY' | 'INVALID_URI' | 'NOT_MAGNET' | 'MISSING_BTIH' | 'BTIH_TOO_SHORT'
    }
  }

  function parseMagnet(raw) {
    const trimmed = (raw ?? '').trim();
    if (!trimmed) throw new MagnetError('EMPTY', 'magnet is empty');

    let url;
    try {
      url = new URL(trimmed);
    } catch {
      throw new MagnetError('INVALID_URI', 'invalid magnet URI');
    }

    if (url.protocol.toLowerCase() !== 'magnet:') {
      throw new MagnetError('NOT_MAGNET', 'not a magnet URI');
    }

    const xt = url.searchParams.get('xt') || '';
    if (!xt.startsWith(BTIH_PREFIX)) {
      throw new MagnetError('MISSING_BTIH', 'magnet missing btih');
    }

    const btih = xt.slice(BTIH_PREFIX.length).trim();
    if (btih.length < MIN_BTIH_LEN) {
      throw new MagnetError('BTIH_TOO_SHORT', 'magnet btih too short');
    }

    return {
      uri: trimmed,
      btih,
      dn: url.searchParams.get('dn') || '',
      trackers: url.searchParams.getAll('tr').length,
    };
  }

  function isValidMagnet(raw) {
    try {
      parseMagnet(raw);
      return true;
    } catch {
      return false;
    }
  }

  const api = { BTIH_PREFIX, MIN_BTIH_LEN, MagnetError, parseMagnet, isValidMagnet };

  if (typeof module !== 'undefined' && module.exports) {
    module.exports = api;
  } else {
    root.Lodestone = Object.assign(root.Lodestone || {}, api);
  }
})(typeof self !== 'undefined' ? self : globalThis);
