(function () {
    var darkSheet = document.getElementById('theme-dark');
    var lightSheet = document.getElementById('theme-light');

    // localStorage throws in Safari private mode and with blocked storage. This
    // script runs synchronously in <head>, so an uncaught throw would leave the
    // page unthemed.
    function readStored() {
        try {
            return localStorage.getItem('theme');
        } catch (e) {
            return null;
        }
    }

    function writeStored(theme) {
        try {
            localStorage.setItem('theme', theme);
        } catch (e) {
            /* preference is lost on reload, but the toggle still works */
        }
    }

    var stored = readStored();

    function getActiveTheme() {
        if (stored === 'dark' || stored === 'light') return stored;
        return window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
    }

    function applyThemeColor(theme) {
        // Both theme-color metas are media-scoped, so an override has to
        // overwrite each of them; whichever one the browser picks must agree.
        var themeColor = theme === 'dark' ? '#0b0b0a' : '#f7f7f4';
        var metas = document.querySelectorAll('meta[name="theme-color"]');
        for (var i = 0; i < metas.length; i++) {
            metas[i].content = themeColor;
        }
    }

    function applyTheme(theme) {
        if (theme === 'dark') {
            darkSheet.media = 'all';
            lightSheet.media = 'not all';
        } else {
            lightSheet.media = 'all';
            darkSheet.media = 'not all';
        }
        applyThemeColor(theme);
    }

    var currentTheme = getActiveTheme();

    // Without a stored override the stylesheets and the theme-color metas are
    // both media-scoped, so the browser follows the OS on its own — including
    // live appearance changes. Only an override needs applying here.
    if (stored) {
        applyTheme(currentTheme);
    }

    document.addEventListener('DOMContentLoaded', function () {
        var toggle = document.getElementById('theme-toggle');
        if (!toggle) return;

        // Pressed means dark mode is active.
        function syncPressed() {
            toggle.setAttribute('aria-pressed', String(currentTheme === 'dark'));
        }

        syncPressed();

        toggle.addEventListener('click', function () {
            currentTheme = currentTheme === 'dark' ? 'light' : 'dark';
            stored = currentTheme;
            writeStored(currentTheme);
            applyTheme(currentTheme);
            syncPressed();
        });

        // With no stored override the media-scoped stylesheets follow OS
        // appearance changes on their own, but currentTheme (and with it the
        // toggle's next-click direction and aria-pressed) would go stale.
        window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', function (e) {
            if (stored) return;
            currentTheme = e.matches ? 'dark' : 'light';
            syncPressed();
        });
    });
})();
