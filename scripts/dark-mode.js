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

    // The screenshots ship in both appearances as a <picture> whose dark
    // <source> is media-scoped like the stylesheets, so an override has to flip
    // it the same way. Runs against whatever is parsed so far — in <head> that
    // is nothing, and the DOMContentLoaded pass below picks them up.
    function applyScreenshots(theme) {
        var sources = document.querySelectorAll('picture source[data-theme]');
        for (var i = 0; i < sources.length; i++) {
            sources[i].media = sources[i].getAttribute('data-theme') === theme ? 'all' : 'not all';
        }
    }

    // Icon links carry the same media queries, but browsers honor media on
    // rel="icon" inconsistently and settle on one icon rather than re-running
    // the queries later. So this runs on every theme change, override or not,
    // and re-inserts each link to make the browser look again.
    function applyIcons(theme) {
        var icons = document.querySelectorAll('link[rel="icon"][data-theme]');
        for (var i = 0; i < icons.length; i++) {
            var icon = icons[i];
            icon.media = icon.getAttribute('data-theme') === theme ? 'all' : 'not all';
            icon.parentNode.removeChild(icon);
            document.head.appendChild(icon);
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
        applyScreenshots(theme);
    }

    var currentTheme = getActiveTheme();

    // Without a stored override the stylesheets, the screenshot sources, and the
    // theme-color metas are all media-scoped, so the browser follows the OS on
    // its own — including live appearance changes. Only an override needs
    // applying here. The icons are the exception noted above.
    if (stored) {
        applyTheme(currentTheme);
    }
    applyIcons(currentTheme);

    document.addEventListener('DOMContentLoaded', function () {
        // The <picture> elements didn't exist when an override was applied above.
        if (stored) {
            applyScreenshots(currentTheme);
        }

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
            applyIcons(currentTheme);
            syncPressed();
        });

        // With no stored override the media-scoped stylesheets and screenshot
        // sources follow OS appearance changes on their own, but the icons need
        // the nudge, and currentTheme (with it the toggle's next-click direction
        // and aria-pressed) would go stale.
        window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', function (e) {
            if (stored) return;
            currentTheme = e.matches ? 'dark' : 'light';
            applyIcons(currentTheme);
            syncPressed();
        });
    });
})();
