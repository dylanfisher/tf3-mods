// React state that is remembered per visitor (src/lib/storage.ts). The server render and the first client render use
// `defaults` (so hydration matches); after mount the stored value is read once, passed through `validate` (which
// keeps only what is still valid and fills the rest from the defaults), and from then on every change is saved.
// `ready` turns true after the restore: effects that must not run on the defaults (hash links) wait for it.
import { useEffect, useState, type Dispatch, type SetStateAction } from "react";
import { readStore, writeStore } from "./storage.ts";

export function usePersistentState<T>(
  key: string,
  defaults: T,
  validate: (stored: unknown, defaults: T) => T,
): [T, Dispatch<SetStateAction<T>>, boolean] {
  const [state, setState] = useState<T>(defaults);
  const [ready, setReady] = useState(false);
  useEffect(() => {
    const stored = readStore(key);
    if (stored !== undefined) setState((cur) => validate(stored, cur));
    setReady(true);
  }, [key]); // eslint-disable-line react-hooks/exhaustive-deps
  useEffect(() => {
    if (ready) writeStore(key, state);
  }, [ready, key, state]);
  return [state, setState, ready];
}
