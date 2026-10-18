// The units runs created besides the paired ones (districts, Works ...): name, run, the source's columns, shot link.
import { cap } from "@/lib/format";
import { lightboxAttrs } from "@/lib/lightbox";
import type { CompareModel, ModelRun, UnitNames } from "../types";
import { H2, Hint, RunName, RunTable } from "./parts";

export function ExtrasTable({ extras, unit, runName, runOf }: { extras: NonNullable<CompareModel["extras"]>; unit: UnitNames; runName: UnitNames; runOf: (id: string) => ModelRun }) {
  return (
    <>
      <H2>{extras.title}</H2>
      <Hint className="mb-2.5">{extras.description}</Hint>
      <RunTable
        first={cap(unit.one)}
        runs={[]}
        after={[{ label: cap(runName.one) }, ...extras.columns.map((c) => ({ label: c, className: "text-right" })), { label: "Shot" }]}
        empty="none"
        rows={extras.rows.map((x, i) => ({
          key: String(i),
          label: x.name,
          cells: [],
          after: [
            <RunName run={runOf(x.run)} />,
            ...x.cells,
            x.img ? <a href={x.img.full} {...lightboxAttrs({ src: x.img.full, title: x.shotName ?? x.name })} className="text-brand-text hover:underline">{x.shotName}</a> : "-",
          ],
        }))}
      />
    </>
  );
}
