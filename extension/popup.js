(function () {
  'use strict';

  const { validateTransmissionConfig, buildRpcUrl } = self.Lodestone;

  const hostInput = document.getElementById('host');
  const authInput = document.getElementById('auth');
  const statusEl = document.getElementById('status');
  const form = document.getElementById('options-form');

  // Match patterns can't include a port (the WebExtensions permission model
  // ignores ports entirely), so the pattern covers the host only -- the
  // actual host:port still goes to fetch() itself in transmission-client.js.
  function originPatternFor(host) {
    const u = new URL(buildRpcUrl(host));
    return `${u.protocol}//${u.hostname}/*`;
  }

  function setStatus(message, isError) {
    statusEl.textContent = message;
    statusEl.classList.toggle('error', Boolean(isError));
  }

  let loadedHost = '';

  async function loadSaved() {
    const { transmission_host = '', transmission_auth = '' } =
      await browser.storage.local.get(['transmission_host', 'transmission_auth']);
    hostInput.value = transmission_host;
    authInput.value = transmission_auth;
    loadedHost = transmission_host;
  }

  function finishSave(host, auth, oldHost, newPattern) {
    // permissions.request() must be called with no preceding `await`, as the
    // direct, synchronous continuation of the submit event -- an async gap
    // beforehand loses the user-gesture association and Safari silently
    // declines to prompt at all.
    return browser.permissions.request({ origins: [newPattern] }).then(
      async (granted) => {
        if (!granted) {
          setStatus(`Permission to reach ${newPattern} was denied -- settings not saved.`, true);
          return;
        }
        if (oldHost && oldHost !== host) {
          const oldPattern = originPatternFor(oldHost);
          if (oldPattern !== newPattern) {
            await browser.permissions.remove({ origins: [oldPattern] }).catch(() => {});
          }
        }
        await browser.storage.local.set({ transmission_host: host, transmission_auth: auth });
        loadedHost = host;
        setStatus('Saved.', false);
      },
      (err) => {
        setStatus(`Permission request failed: ${err.message}`, true);
      }
    );
  }

  form.addEventListener('submit', (event) => {
    event.preventDefault();
    const host = hostInput.value.trim();
    const auth = authInput.value.trim();

    try {
      validateTransmissionConfig(host, auth);
    } catch (err) {
      setStatus(err.message, true);
      return;
    }

    setStatus('Requesting permission...', false);
    finishSave(host, auth, loadedHost, originPatternFor(host));
  });

  loadSaved();
})();
