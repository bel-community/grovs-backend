// One platform decision, one navigation attempt, one fallback. The detectors overlap
// (an iPhone UA contains "Mac", Android contains "Linux"), so there must be no fallthrough.
function pickQuickLinkTarget(ios_phone, ios_tablet, android_phone, android_tablet, desktop, mac, windows, linux) {
  if (isIphone()) return ios_phone;
  if (isIpad()) return ios_tablet || ios_phone;
  if (isAndroidPhone()) return android_phone;
  if (isAndroidTablet()) return android_tablet || android_phone;
  if (isMac()) return mac || desktop;
  if (isWindows()) return windows || desktop;
  if (isLinux()) return linux || desktop;
  return null;
}

function navigateTo(target) {
  if (!target || /^(javascript|data|vbscript|blob|file|about):/i.test(target.replace(/[\x00-\x20]/g, ""))) {
    return false;
  }
  window.location.href = target;
  return true;
}

function handleQuickLinkRedirect(ios_phone, ios_tablet, android_phone, android_tablet, desktop, mac, windows, linux) {
  var target = pickQuickLinkTarget(ios_phone, ios_tablet, android_phone, android_tablet, desktop, mac, windows, linux);
  if (!navigateTo(target)) {
    window.location.href = "https://grovs.io";
  }
}
