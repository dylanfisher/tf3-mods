// Labelled form controls shared by every island (filters, browsers, the comparison viewer, the Name lab): a shadcn
// (Base UI) Select or Checkbox inside a <label>, muted label text, the value in ink.
import type { ReactNode } from "react";
import { Checkbox } from "@/components/ui/checkbox";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { cn } from "@/lib/utils";

export interface Option { value: string; label: string }

export function LabeledSelect({ label, value, options, onChange, disabled, hideLabel, ariaLabel, title, className, triggerClassName }: {
  label: string;
  value: string;
  options: Option[];
  onChange: (v: string) => void;
  disabled?: boolean;
  /** label only for screen readers (the options say what it is, e.g. "All seeds") */
  hideLabel?: boolean;
  /** accessible name when it should differ from the visible label ("Run A" for "A") */
  ariaLabel?: string;
  title?: string;
  className?: string;
  triggerClassName?: string;
}) {
  return (
    <label className={cn("inline-flex min-w-0 items-center gap-1.5 text-sm text-muted-foreground", className)} title={title}>
      {!hideLabel && <span className="shrink-0">{label}</span>}
      <Select items={options} value={value} onValueChange={(v) => onChange((v as string) ?? "")} disabled={disabled}>
        <SelectTrigger aria-label={ariaLabel ?? label} className={cn("max-w-full min-w-0 bg-background text-foreground", triggerClassName)}>
          <SelectValue />
        </SelectTrigger>
        <SelectContent alignItemWithTrigger={false}>
          {options.map((o) => (
            <SelectItem key={o.value} value={o.value}>{o.label}</SelectItem>
          ))}
        </SelectContent>
      </Select>
    </label>
  );
}

export function LabeledCheckbox({ label, checked, onChange, title, disabled }: {
  label: ReactNode;
  checked: boolean;
  onChange: (v: boolean) => void;
  title?: string;
  disabled?: boolean;
}) {
  return (
    <label className="inline-flex cursor-pointer items-center gap-2 text-sm text-muted-foreground select-none" title={title}>
      <Checkbox checked={checked} onCheckedChange={(v) => onChange(!!v)} disabled={disabled} />
      {label}
    </label>
  );
}
