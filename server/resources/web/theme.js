// Theme is always owned by the operating system, never a saved preference.
(function () {
    var theme = window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light";
    document.documentElement.dataset.theme = theme;
    try { localStorage.removeItem("pitpulse-theme"); } catch (_) {}
    var meta = document.querySelector('meta[name="theme-color"]');
    if (meta) meta.setAttribute("content", theme === "light" ? "#f2f3f5" : "#0e0e10");
})();
