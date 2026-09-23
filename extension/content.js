document.addEventListener(
  'click',
  (event) => {
    const target = event.target;
    if (!(target instanceof Element)) return;

    const anchor = target.closest('a[href^="magnet:"]');
    if (!anchor) return;

    const uri = anchor.getAttribute('href');
    event.preventDefault();
    event.stopPropagation();

    browser.runtime.sendMessage({ type: 'ADD_MAGNET', uri }).catch(() => {
      // No listener, or extension context invalidated -- nothing to do.
    });
  },
  true // capture phase, so we win even if page JS calls stopPropagation on bubble
);
