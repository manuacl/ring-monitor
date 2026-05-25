// Catalog of predefined color themes for the ring arcs, plus the
// resolver that picks the right concrete color given the current
// platform state.
//
// What lives here:
//   - THEMES         — list of {id, label, lightColor, darkColor}
//   - THEMES_BY_ID   — id → theme lookup
//   - resolveColor() — pure dispatch from a theme id to a concrete color
//
// What does NOT live here:
//   - light/dark detection (Theme adapter exposes isDarkMode)
//   - the system highlight (Theme adapter exposes highlightColor)
//   - the user's custom colors (ConfigStore exposes them)
//
// The two non-data themes are "system" (forwards the platform highlight
// straight through) and "custom" (picks between the user's two custom
// colors). Dispatch uses a lookup map — no nested ternaries.
//
// Dual-loaded by QML (`import "ColorThemes.js" as ColorThemes`) and Node
// (via the module.exports shim at the bottom).

var THEMES = [
    { id: "system", label: "System", lightColor: null,      darkColor: null      },
    { id: "blue",   label: "Blue",   lightColor: "#1d6fa5", darkColor: "#3daee9" },
    { id: "green",  label: "Green",  lightColor: "#2d8659", darkColor: "#3dd685" },
    { id: "orange", label: "Orange", lightColor: "#c45a1c", darkColor: "#f67e3c" },
    { id: "violet", label: "Violet", lightColor: "#6a3d9a", darkColor: "#a87fd1" },
    { id: "red",    label: "Red",    lightColor: "#b03030", darkColor: "#e25555" },
    { id: "custom", label: "Custom", lightColor: null,      darkColor: null      },
];

var THEMES_BY_ID = {};
for (var i = 0; i < THEMES.length; i++) {
    THEMES_BY_ID[THEMES[i].id] = THEMES[i];
}

// Resolve the user's colorMode + the auto-detected system isDark into
// the effective dark/light boolean the color resolver consumes.
// "auto" trusts the detected systemIsDark (the Theme adapter sources
// it from Qt.styleHints.colorScheme, the canonical KDE signal since
// KF 6.22); "light"/"dark" force the answer regardless. Unknown
// modes (or a stale config value) fall back to "auto" so the value
// is always defined.
function effectiveIsDark(mode, systemIsDark) {
    var resolvers = {
        auto: function () { return systemIsDark; },
        light: function () { return false; },
        dark: function () { return true; },
    };
    var pick = resolvers[mode] || resolvers.auto;
    return pick();
}

// Lookup-map dispatch for the two non-data themes; data themes fall
// through to the lightColor/darkColor branch. Unknown ids fall back to
// "system" so a stale config value can never produce undefined.
function resolveColor(themeId, isDark, systemHighlight, customLight, customDark) {
    var theme = THEMES_BY_ID[themeId] || THEMES_BY_ID.system;
    var resolvers = {
        system: function () { return systemHighlight; },
        custom: function () { return isDark ? customDark : customLight; },
    };
    if (resolvers[theme.id]) return resolvers[theme.id]();
    return isDark ? theme.darkColor : theme.lightColor;
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        THEMES: THEMES,
        THEMES_BY_ID: THEMES_BY_ID,
        effectiveIsDark: effectiveIsDark,
        resolveColor: resolveColor,
    };
}
