// The theme choice: "system" (follow prefers-color-scheme), "light" or "dark". It lives as data-theme on <html>
// (theme.css switches color-scheme on it) and, when saved, in localStorage("theme"); BaseLayout's inline head script
// re-applies the saved one before first paint (an inline script cannot import this module, so it repeats the read).
// Everything that changes the theme goes through setTheme: the toggle (ThemeToggle.astro) listens for the event to
// show the current mode.

export type ThemeMode = "system" | "light" | "dark";
export const THEME_MODES: readonly ThemeMode[] = ["system", "light", "dark"];
export const THEME_EVENT = "site-theme";

export function currentTheme(): ThemeMode {
  const t = document.documentElement.dataset.theme;
  return t === "light" || t === "dark" ? t : "system";
}

/** Applies a mode; `persist: false` for a one-off (a #theme= link) that leaves the visitor's saved choice alone. */
export function setTheme(mode: ThemeMode, { persist = true }: { persist?: boolean } = {}): void {
  if (mode === "system") delete document.documentElement.dataset.theme;
  else document.documentElement.dataset.theme = mode;
  if (persist) {
    try {
      if (mode === "system") localStorage.removeItem("theme");
      else localStorage.setItem("theme", mode);
    } catch { /* storage unavailable */ }
  }
  document.dispatchEvent(new CustomEvent<ThemeMode>(THEME_EVENT, { detail: mode }));
}
