/* The only build is for macOS, so the download CTA is inert everywhere else.
   This runs synchronously in <head> so the disabled state paints on the first
   frame instead of flashing an enabled button at non-Mac visitors. */
(function () {
    function isMac() {
        var uaData = navigator.userAgentData;
        if (uaData && uaData.platform) return uaData.platform === 'macOS';

        // iPadOS reports navigator.platform as "MacIntel" as well; multi-touch
        // is what separates it from a real Mac.
        if (navigator.maxTouchPoints > 1) return false;

        return /Mac/i.test(navigator.platform || navigator.userAgent || '');
    }

    if (isMac()) return;

    // Drives the faded styling and the label swap in styles/index-common.css.
    document.documentElement.classList.add('not-macos');

    document.addEventListener('DOMContentLoaded', function () {
        var btn = document.getElementById('release-link');
        if (!btn) return;

        // Dropping href makes it unclickable and unfocusable; the explicit role
        // keeps it announced as a link so aria-disabled has something to apply
        // to.
        btn.removeAttribute('href');
        btn.setAttribute('role', 'link');
        btn.setAttribute('aria-disabled', 'true');
    });
})();
