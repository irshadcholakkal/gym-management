(() => {
  window.gymproPushSubscribe = async key => {
    if (!('serviceWorker' in navigator) || !('PushManager' in window) || !('Notification' in window)) throw new Error('This browser does not support web push. In-app reminders remain available.');
    if (!key) throw new Error('Push has not been configured by your administrator.');
    const permission = await Notification.requestPermission();
    if (permission !== 'granted') throw new Error('Push permission was not granted. In-app reminders remain available.');
    const registration = await navigator.serviceWorker.ready;
    const raw = atob(key.replace(/-/g, '+').replace(/_/g, '/'));
    const bytes = Uint8Array.from(raw, c => c.charCodeAt(0));
    const subscription = await registration.pushManager.getSubscription() || await registration.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: bytes });
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
