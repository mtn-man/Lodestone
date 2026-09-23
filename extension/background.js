(function () {
  'use strict';

  const { parseMagnet } = self.Lodestone;
  const { addMagnet } = self.Lodestone;

  const BADGE_CLEAR_MS = 4000;
  const MENU_ID = 'lodestone-add-magnet';
  let badgeTimer = null;

  async function showResult(ok, error) {
    clearTimeout(badgeTimer);
    await browser.action.setBadgeText({ text: ok ? 'OK' : 'ERR' });
    await browser.action.setBadgeBackgroundColor({ color: ok ? '#2e7d32' : '#c62828' });
    await browser.action.setTitle({ title: ok ? 'Lodestone: magnet added' : `Lodestone error: ${error}` });
    badgeTimer = setTimeout(async () => {
      await browser.action.setBadgeText({ text: '' });
      await browser.action.setTitle({ title: 'Lodestone' });
    }, BADGE_CLEAR_MS);
  }

  async function handleMagnetUri(uri) {
    let parsed;
    try {
      parsed = parseMagnet(uri);
    } catch (err) {
      await showResult(false, err.message);
      return { ok: false, error: err.message };
    }

    const { transmission_host: host, transmission_auth: auth } =
      await browser.storage.local.get(['transmission_host', 'transmission_auth']);

    if (!host) {
      const message = 'Set a Transmission host in Lodestone options.';
      await showResult(false, message);
      return { ok: false, error: message };
    }

    try {
      await addMagnet(parsed.uri, { host, auth });
      await showResult(true);
      return { ok: true };
    } catch (err) {
      await showResult(false, err.message);
      return { ok: false, error: err.message };
    }
  }

  browser.runtime.onMessage.addListener((message) => {
    if (!message || message.type !== 'ADD_MAGNET') return undefined;
    return handleMagnetUri(message.uri);
  });

  browser.contextMenus.onClicked.addListener((info) => {
    if (info.menuItemId === MENU_ID && info.linkUrl) {
      handleMagnetUri(info.linkUrl);
    }
  });

  browser.action.onClicked.addListener(() => {
    browser.runtime.openOptionsPage();
  });

  (async () => {
    await browser.contextMenus.removeAll();
    await browser.contextMenus.create({
      id: MENU_ID,
      title: 'Add magnet to Transmission',
      contexts: ['link'],
    });
  })();
})();
