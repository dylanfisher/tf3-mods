// Visitor state in localStorage, one scheme for the whole site: keys "tf3-site:<modId>/<section>/<what>" (data names,
// not URLs), JSON values, and every access in try/catch (storage may be missing, full or blocked; the pages work
// without it). React islands use usePersistentState (./use-persistent-state.ts); plain code reads and writes here.

const STORAGE_PREFIX = "tf3-site:";

/** The stored value of `key` (JSON), or undefined when missing, unreadable or blocked. */
export function readStore(key: string): unknown {
  try {
    const raw = localStorage.getItem(STORAGE_PREFIX + key);
    return raw == null ? undefined : JSON.parse(raw);
  } catch {
    return undefined;
  }
}

export function writeStore(key: string, value: unknown): void {
  try {
    localStorage.setItem(STORAGE_PREFIX + key, JSON.stringify(value));
  } catch { /* storage unavailable */ }
}

export function removeStore(key: string): void {
  try {
    localStorage.removeItem(STORAGE_PREFIX + key);
  } catch { /* storage unavailable */ }
}

/**
 * Moves a value kept under an older, unprefixed key to `key` once: when `key` is empty and `legacyKey` holds JSON,
 * that value is copied over and the old key removed. Visitors keep their state across a key rename.
 */
export function migrateStore(key: string, legacyKey: string): void {
  try {
    if (localStorage.getItem(STORAGE_PREFIX + key) != null) return;
    const old = localStorage.getItem(legacyKey);
    if (old == null) return;
    JSON.parse(old);
    localStorage.setItem(STORAGE_PREFIX + key, old);
    localStorage.removeItem(legacyKey);
  } catch { /* unreadable: leave both alone */ }
}

/** A plain object from storage (anything else: {}), for validators that pick known fields. */
export const asRecord = (v: unknown): Record<string, unknown> =>
  v && typeof v === "object" && !Array.isArray(v) ? (v as Record<string, unknown>) : {};
