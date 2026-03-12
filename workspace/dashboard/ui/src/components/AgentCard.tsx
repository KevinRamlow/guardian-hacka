import React from 'react';
import { Clock, RefreshCw, Layers, ArrowRight } from 'lucide-react';
import StatusBadge from './StatusBadge';
import type { ActiveAgent } from '../types';

interface AgentCardProps {
  agent: ActiveAgent;
  onClick: (sessionKey: string) => void;
}

const roleColors: Record<string, string> = {
  developer: 'bg-role-developer/15 text-role-developer border-role-developer/20',
  reviewer: 'bg-role-reviewer/15 text-role-reviewer border-role-reviewer/20',
  architect: 'bg-role-architect/15 text-role-architect border-role-architect/20',
  'guardian-tuner': 'bg-role-guardian/15 text-role-guardian border-role-guardian/20',
  guardian: 'bg-role-guardian/15 text-role-guardian border-role-guardian/20',
  debugger: 'bg-role-debugger/15 text-role-debugger border-role-debugger/20',
};

function getHealthColor(color: string): string {
  switch (color) {
    case 'green': return 'bg-emerald-500';
    case 'yellow': return 'bg-amber-500';
    case 'orange': return 'bg-orange-500';
    case 'red': return 'bg-red-500';
    default: return 'bg-zinc-500';
  }
}

function getProgressColor(percent: number): string {
  if (percent < 50) return 'bg-emerald-500';
  if (percent < 75) return 'bg-amber-500';
  if (percent < 90) return 'bg-orange-500';
  return 'bg-red-500';
}

const AgentCard: React.FC<AgentCardProps> = ({ agent, onClick }) => {
  const progressPercent = Math.min(
    100,
    agent.timeoutMin > 0 ? (agent.runtimeMs / (agent.timeoutMin * 60000)) * 100 : 0
  );

  const roleBadge = agent.role
    ? roleColors[agent.role] || 'bg-zinc-500/15 text-zinc-400 border-zinc-500/20'
    : null;

  return (
    <div
      onClick={() => onClick(agent.sessionKey)}
      className="bg-bg-card border border-border-primary rounded-xl p-4 hover:border-border-secondary hover:bg-bg-hover transition-all duration-150 cursor-pointer group animate-fade-in"
    >
      {/* Header */}
      <div className="flex items-start justify-between mb-3">
        <div className="flex items-center gap-2 min-w-0 flex-1">
          <div className={`h-2 w-2 rounded-full ${getHealthColor(agent.health.color)}`} />
          <span className="text-sm font-medium text-text-primary truncate">{agent.label}</span>
        </div>
        <div className="flex items-center gap-2 shrink-0">
          <StatusBadge status={agent.status} />
          <ArrowRight
            size={14}
            className="text-text-muted opacity-0 group-hover:opacity-100 transition-opacity"
          />
        </div>
      </div>

      {/* Role + Task */}
      <div className="flex items-center gap-2 mb-3 flex-wrap">
        {roleBadge && (
          <span className={`text-[10px] font-medium px-2 py-0.5 rounded-full border ${roleBadge}`}>
            {agent.role}
          </span>
        )}
        <span className="text-xs text-text-muted font-mono">{agent.taskId}</span>
      </div>

      {/* Linear title */}
      {agent.linear && (
        <div className="text-xs text-text-secondary mb-3 truncate">
          {agent.linear.title}
        </div>
      )}

      {/* Progress bar — eval-specific or timeout-based */}
      {agent.status === 'eval_running' ? (
        <div className="mb-3">
          {/* Dataset from label */}
          <div className="flex items-center justify-between text-[10px] text-text-muted mb-1">
            <span className="text-cyan-400 font-medium">
              {agent.label.replace(/^eval:/, '').trim()}
            </span>
            {agent.evalProgress ? (
              <span className="font-mono">
                {agent.evalProgress.completed}/{agent.evalProgress.total} cases
              </span>
            ) : (
              <span className="font-mono">starting...</span>
            )}
          </div>
          <div className="h-2 bg-bg-tertiary rounded-full overflow-hidden">
            <div
              className="h-full rounded-full transition-all duration-500 bg-cyan-500"
              style={{ width: `${agent.evalProgress?.percent ?? 0}%` }}
            />
          </div>
          <div className="flex items-center justify-between text-[10px] text-text-muted mt-1">
            <span>{agent.evalProgress?.percent ?? 0}%</span>
            <div className="flex gap-2">
              {agent.evalProgress && agent.evalProgress.errors > 0 && (
                <span className="text-red-400 font-mono">
                  {agent.evalProgress.errors} errors
                </span>
              )}
              <span>{agent.runtimeMin}m elapsed</span>
            </div>
          </div>
        </div>
      ) : (
        <div className="mb-3">
          <div className="flex items-center justify-between text-[10px] text-text-muted mb-1">
            <span>{agent.runtimeMin}m elapsed</span>
            <span>ETA {agent.etaMin}m / {agent.timeoutMin}m timeout</span>
          </div>
          <div className="h-1.5 bg-bg-tertiary rounded-full overflow-hidden">
            <div
              className={`h-full rounded-full transition-all duration-500 ${getProgressColor(progressPercent)}`}
              style={{ width: `${progressPercent}%` }}
            />
          </div>
        </div>
      )}

      {/* Footer meta */}
      <div className="flex items-center gap-3 text-[10px] text-text-muted">
        <span className="flex items-center gap-1">
          <Clock size={10} /> {agent.runtimeMin}m
        </span>
        {agent.retries > 0 && (
          <span className="flex items-center gap-1">
            <RefreshCw size={10} /> {agent.retries} retries
          </span>
        )}
        {agent.extensions > 0 && (
          <span className="flex items-center gap-1">
            <Layers size={10} /> {agent.extensions} ext
          </span>
        )}
        <span className="ml-auto text-text-muted">{agent.source}</span>
      </div>

      {/* Health alert */}
      {agent.health.alert && (
        <div className="mt-2 text-[10px] text-orange-400 bg-orange-500/5 border border-orange-500/10 rounded px-2 py-1">
          {agent.health.alert}
        </div>
      )}
    </div>
  );
};

export default React.memo(AgentCard);
