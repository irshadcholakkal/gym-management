(() => {
  let installPrompt = null;
  let installed = false;
  const standalone = () => installed || window.matchMedia?.('(display-mode: standalone)').matches || navigator.standalone === true;
  window.gymproInstallState = () => standalone() ? 'installed' : installPrompt ? 'ready' : 'manual';
  window.addEventListener('beforeinstallprompt', event => {
    event.preventDefault();
    installPrompt = event;
  });
  window.addEventListener('appinstalled', () => { installed = true; installPrompt = null; });
  window.gymproInstallApp = async () => {
    if (standalone()) return 'installed';
    if (installPrompt) {
      const prompt = installPrompt;
      installPrompt = null;
      await prompt.prompt();
      return (await prompt.userChoice).outcome;
    }
    const agent = navigator.userAgent || '';
    if (/iPad|iPhone|iPod/.test(agent) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1)) return 'ios';
    if (/Android/.test(agent)) return 'android';
    if (/Mac/.test(navigator.platform || '')) return 'mac';
    return 'manual';
  };
  window.gymproAppUpdate = async apply => {
    if (!('serviceWorker' in navigator)) return 'unsupported';
    const registration = await navigator.serviceWorker.getRegistration();
    if (!registration) return 'unavailable';
    if (apply && registration.waiting) {
      registration.waiting.postMessage({ type: 'ACTIVATE_UPDATE' });
      return 'applying';
    }
    await registration.update();
    if (registration.installing) {
      await new Promise(resolve => {
        const worker = registration.installing;
        const finish = () => { worker.removeEventListener('statechange', changed); clearTimeout(timer); resolve(); };
        const changed = () => { if (['installed', 'redundant'].includes(worker.state)) finish(); };
        const timer = setTimeout(finish, 15000);
        worker.addEventListener('statechange', changed);
        changed();
      });
    }
    return registration.waiting ? 'ready' : registration.installing ? 'checking' : 'current';
  };
  window.gymproPushStatus = async () => {
    if (!('serviceWorker' in navigator) || !('PushManager' in window) || !('Notification' in window) || !window.isSecureContext) {
      return JSON.stringify({ permission: 'unsupported', subscription: null });
    }
    const registration = await navigator.serviceWorker.getRegistration();
    const subscription = registration ? await registration.pushManager.getSubscription() : null;
    return JSON.stringify({ permission: Notification.permission, subscription: subscription ? subscription.toJSON() : null });
  };
  // This isolates browser/OS display from server delivery; it is not a remote push.
  window.gymproPushTestDisplay = async () => {
    if (!window.isSecureContext || !('serviceWorker' in navigator) || !('Notification' in window)) throw new Error('Use the installed web app or a supported browser over HTTPS.');
    if (Notification.permission !== 'granted') throw new Error('Allow notifications for this app before testing display.');
    const registration = await navigator.serviceWorker.getRegistration();
    if (!registration?.active) throw new Error('The notification service worker is not active. Reload the app and try again.');
    const base = new URL('./', registration.scope);
    await registration.showNotification('GymPro UAE', {
      body: 'Device display test. Your browser can request notifications on this device.',
      tag: 'gympro-display-test', icon: new URL('icons/Icon-192.png', base).href,
      data: { url: new URL('./#/notifications', base).href },
    });
  };
  window.gymproPushSubscribe = async key => {
    if (!('serviceWorker' in navigator) || !('PushManager' in window) || !('Notification' in window)) throw new Error('This browser does not support web push. In-app reminders remain available.');
    if (!window.isSecureContext) throw new Error('Push requires HTTPS.');
    key = (key || '').trim();
    const invalidKey = 'Push is not configured correctly. Ask your administrator to set a valid VAPID public key and rebuild the app. In-app reminders remain available.';
    if (!key) throw new Error('Push has not been configured. In-app reminders remain available.');
    let bytes;
    try {
      if (!/^[A-Za-z0-9_-]{87}=?$/.test(key)) throw new Error();
      const raw = atob(key.replace(/-/g, '+').replace(/_/g, '/'));
      bytes = Uint8Array.from(raw, c => c.charCodeAt(0));
      if (bytes.length !== 65 || bytes[0] !== 4) throw new Error();
      await crypto.subtle.importKey('raw', bytes, { name: 'ECDSA', namedCurve: 'P-256' }, false, ['verify']);
    } catch { throw new Error(invalidKey); }
    if (Notification.permission === 'denied') throw new Error('Notifications are blocked. Allow notifications in your browser site settings and try again.');
    const permission = await Notification.requestPermission();
    if (permission !== 'granted') throw new Error('Push permission was not granted. In-app reminders remain available.');
    const registration = await navigator.serviceWorker.ready;
    let subscription = await registration.pushManager.getSubscription();
    if (subscription) {
      const previous = new Uint8Array(subscription.options.applicationServerKey || []);
      if (previous.length !== bytes.length || previous.some((byte, index) => byte !== bytes[index])) {
        await subscription.unsubscribe();
        subscription = null;
      }
    }
    try {
      subscription ||= await registration.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: bytes });
    } catch (error) {
      if (error.name === 'InvalidAccessError') throw new Error(invalidKey);
      throw error;
    }
    return JSON.stringify(subscription.toJSON());
  };
  if (!('serviceWorker' in navigator)) return;
  window.addEventListener('load', async () => {
    try {
      const registration = await navigator.serviceWorker.register('gympro-sw.js');
      const offerUpdate = () => {
        if (!registration.waiting || !navigator.serviceWorker.controller) return;
        const button = document.createElement('button');
        button.textContent = 'GymPro update ready — reload';
        button.style.cssText = 'position:fixed;bottom:20px;right:20px;z-index:99999;padding:16px;border:1px solid #25664d;background:#e3f1e9;color:#263238;border-radius:12px;cursor:pointer';
        button.onclick = () => registration.waiting.postMessage({ type: 'ACTIVATE_UPDATE' });
        document.body.appendChild(button);
      };
      offerUpdate();
      registration.addEventListener('updatefound', () => registration.installing?.addEventListener('statechange', offerUpdate));
      let refreshing = false;
      let hadController = navigator.serviceWorker.controller !== null;
      navigator.serviceWorker.addEventListener('controllerchange', () => {
        if (!hadController) { hadController = true; return; }
        if (!refreshing && navigator.serviceWorker.controller) { refreshing = true; location.reload(); }
      });
    } catch (error) { console.info('Offline shell unavailable', error.name); }
  });
})();
