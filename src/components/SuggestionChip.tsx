import { LucideIcon } from "lucide-react";
import type { AgentQuickActionDefinition, TelegramSetupQuickActionDefinition } from "../lib/chatQuickActions";

export type SuggestionAction = {
  type: "quick_action";
  actionId: AgentQuickActionDefinition["id"] | TelegramSetupQuickActionDefinition["id"];
};

type Props = {
  icon: LucideIcon;
  label: string;
  action: SuggestionAction;
  onClick: (action: SuggestionAction) => void;
  variant?: "default" | "builder";
};

export function SuggestionChip({ icon: Icon, label, action, onClick, variant = "default" }: Props) {
  const baseClass =
    "flex items-center gap-2 px-4 py-2.5 rounded-full border transition-all text-sm font-medium";
  const toneClass =
    variant === "builder"
      ? "bg-gradient-to-r from-violet-500/18 via-fuchsia-500/14 to-violet-500/18 border-violet-400/45 text-violet-900 shadow-[0_0_22px_rgba(139,92,246,0.32)] hover:shadow-[0_0_26px_rgba(139,92,246,0.45)] hover:border-violet-400/70 hover:text-violet-950"
      : "bg-[var(--bg-tertiary)] hover:bg-[var(--bg-secondary)] border-[var(--glass-border-subtle)] text-[var(--text-secondary)] hover:text-[var(--text-primary)]";
  return (
    <button
      onClick={() => onClick(action)}
      className={`${baseClass} ${toneClass}`}
    >
      <Icon className="w-4 h-4" />
      <span>{label}</span>
    </button>
  );
}
