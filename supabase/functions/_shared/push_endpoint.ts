// Keep test pushes and reminder delivery on the same restricted provider list.
export function isSupportedPushEndpoint(value: unknown): boolean {
  if (typeof value !== 'string' || value.length > 4096) return false;
  try {
    const endpoint = new URL(value);
    if (endpoint.protocol !== 'https:' || endpoint.username || endpoint.password ||
        (endpoint.port && endpoint.port !== '443')) return false;
    const host = endpoint.hostname;
    return host === 'fcm.googleapis.com' ||
      // Chromium's alternate Google GCM endpoint; never rewrite subscription URLs.
      (host === 'jmt17.google.com' && endpoint.pathname.startsWith('/fcm/send/')) ||
      host.endsWith('.push.services.mozilla.com') ||
      host.endsWith('.push.apple.com') ||
      host.endsWith('.notify.windows.com');
  } catch {
    return false;
  }
}
