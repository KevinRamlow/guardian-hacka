import React from 'react';

interface StatusBadgeProps {
  status: string;
  size?: 'sm' | 'md';
}

const statusConfig: Record<string, { bg: string; text: string; dot?: string }> = {
  running: { bg: 'bg-emerald-500/10', text: 'text-emerald-400', dot: 'bg-emerald-400' },
  eval_running: { bg: 'bg-cyan-500/10', text: 'text-cyan-400', dot: 'bg-cyan-400' },
  callback_pending: { bg: 'bg-amber-500/10', text: 'text-amber-400', dot: 'bg-amber-400' },
  done: { bg: 'bg-emerald-500/10', text: 'text-emerald-400' },
  error: { bg: 'bg-red-500/10', text: 'text-red-400' },
  failed: { bg: 'bg-red-500/10', text: 'text-red-400' },
  todo: { bg: 'bg-zinc-500/10', text: 'text-zinc-400' },
  in_progress: { bg: 'bg-blue-500/10', text: 'text-blue-400', dot: 'bg-blue-400' },
  zombie: { bg: 'bg-orange-500/10', text: 'text-orange-400' },
  ok: { bg: 'bg-emerald-500/10', text: 'text-emerald-400' },
  down: { bg: 'bg-red-500/10', text: 'text-red-400' },
  partial: { bg: 'bg-amber-500/10', text: 'text-amber-400' },
  active: { bg: 'bg-emerald-500/10', text: 'text-emerald-400' },
  paused: { bg: 'bg-amber-500/10', text: 'text-amber-400' },
  online: { bg: 'bg-emerald-500/10', text: 'text-emerald-400' },
  offline: { bg: 'bg-red-500/10', text: 'text-red-400' },
  unknown: { bg: 'bg-zinc-500/10', text: 'text-zinc-400' },
};

const StatusBadge: React.FC<StatusBadgeProps> = ({ status, size = 'sm' }) => {
  const safeStatus = status ?? 'unknown';
  const config = statusConfig[safeStatus] || { bg: 'bg-zinc-500/10', text: 'text-zinc-400' };
  const sizeClasses = size === 'sm' ? 'px-2 py-0.5 text-xs' : 'px-2.5 py-1 text-sm';

  return (
    <span
      className={`inline-flex items-center gap-1.5 rounded-full font-medium font-mono ${config.bg} ${config.text} ${sizeClasses}`}
    >
      {config.dot && (
        <span className={`h-1.5 w-1.5 rounded-full ${config.dot} animate-pulse-dot`} />
      )}
      {safeStatus.replace(/_/g, ' ')}
    </span>
  );
};

export default React.memo(StatusBadge);
