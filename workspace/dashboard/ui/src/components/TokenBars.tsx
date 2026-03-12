import React from 'react';
import type { SessionToken } from '../types';

interface TokenBarsProps {
  tokens: SessionToken[];
}

function getTokenColor(percent: number): string {
  if (percent < 50) return 'bg-emerald-500';
  if (percent < 75) return 'bg-amber-500';
  if (percent < 90) return 'bg-orange-500';
  return 'bg-red-500';
}

function getTokenTextColor(percent: number): string {
  if (percent < 50) return 'text-emerald-400';
  if (percent < 75) return 'text-amber-400';
  if (percent < 90) return 'text-orange-400';
  return 'text-red-400';
}

function formatTokens(n: number): string {
  if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(1)}M`;
  if (n >= 1_000) return `${(n / 1_000).toFixed(0)}K`;
  return String(n);
}

const TokenBars: React.FC<TokenBarsProps> = ({ tokens }) => {
  if (!tokens.length) return null;

  return (
    <div className="bg-bg-card border border-border-primary rounded-xl p-4">
      <h3 className="text-xs uppercase tracking-wider text-text-muted font-medium mb-3">
        Token Usage
      </h3>
      <div className="space-y-2.5">
        {tokens.map((token) => (
          <div key={`${token.agent}-${token.model}`}>
            <div className="flex items-center justify-between mb-1">
              <div className="flex items-center gap-2 min-w-0">
                <span className="text-xs text-text-primary font-medium truncate">
                  {token.agent}
                </span>
                <span className="text-[10px] text-text-muted font-mono">{token.model}</span>
              </div>
              <span className={`text-xs font-mono ${getTokenTextColor(token.percent)}`}>
                {formatTokens(token.used)} / {formatTokens(token.total)}
              </span>
            </div>
            <div className="h-1.5 bg-bg-tertiary rounded-full overflow-hidden">
              <div
                className={`h-full rounded-full transition-all duration-500 ${getTokenColor(token.percent)}`}
                style={{ width: `${Math.min(100, token.percent)}%` }}
              />
            </div>
          </div>
        ))}
      </div>
    </div>
  );
};

export default React.memo(TokenBars);
