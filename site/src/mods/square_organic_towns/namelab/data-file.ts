// The Name lab's data file (export_names.py -> plans/square_organic_towns/names/data.json; gitignored because it holds
// the game's town lists): emitted as a hashed build asset (the island fetches it, so the page stays small) and read at
// build time for the section card's facts. The glob below is the only place the path is written.
import { readJson } from "@/lib/repo";
import type { NameData } from "./types.ts";

const urls = import.meta.glob<string>("../../../../../plans/square_organic_towns/names/data.json", { query: "?url", import: "default", eager: true });
const [file, url] = Object.entries(urls)[0] ?? [];

/** Asset URL for the island, or undefined when the data has not been exported yet. */
export const NAME_DATA_URL: string | undefined = url;

/** The data at build time (the fields the card counts), or undefined. */
export const readNameData = () =>
  file ? readJson<Pick<NameData, "lang" | "towns">>(file.replace(/^(\.\.\/)+/, "")) : undefined;
