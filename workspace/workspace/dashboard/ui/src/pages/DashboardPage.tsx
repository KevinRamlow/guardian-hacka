import React from 'react';
import StatsBar from '../components/StatsBar';
import AgentCard from '../components/AgentCard';
import TokenBars from '../components/TokenBars';
import SystemHealth from '../components/SystemHealth';
import ActivityTimeline from '../components/ActivityTimeline';
import type { DashboardState } from '../types';

interface DashboardPageProps {
  state: DashboardState;
  onSelectAgent: (sessionKey: string) => void;
}

const DashboardPage: React.FC<DashboardPageProps> = ({ state, onSelectAgent }) => {
  return (
    <div className="space-y-6 animate-fade-in">
      {/* Stats */}
      <StatsBar stats={state.stats} system={state.system} />

      {/* Alerts */}
      {state.alerts.length > 0 && (
        <div className="space-y-2">
          {state.alerts.map((alert, i) => (
            <div
              key={i}
              className={`rounded-xl px-4 py-3 text-sm border ${
                alert.type === 'error'
                  ? 'bg-red-500/5 border-red-500/10 text-red-400'
                  : alert.type === 'warning'
                  ? 'bg-amber-500/5 border-amber-500/10 text-amber-400'
                  : 'bg-blue-500/5 border-blue-500/10 text-blue-400'
              }`}
            >
              {alert.message}
            </div>
          ))}
        </div>
      )}

      {/* Active agents */}
      <div>
        <h2 className="text-xs uppercase tracking-wider text-text-muted font-medium mb-3">
          Active Agents ({state.active.length})
        </h2>
        {state.active.length > 0 ? (
          <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-3">
            {state.active.map((agent) => (
              <AgentCard key={agent.sessionKey} agent={agent} onClick={onSelectAgent} />
            ))}
          </div>
        ) : (
          <div className="bg-bg-card border border-border-primary rounded-xl p-8 text-center text-text-muted text-sm">
            No active agents
          </div>
        )}
      </div>

      {/* Bottom grid: tokens + health + activity */}
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-4">
        <div className="lg:col-span-1 space-y-4">
          <TokenBars tokens={state.tokens} />
          <SystemHealth
            system={state.system}
            remote={state.remote}
            billy={state.billy}
          />
        </div>
        <div className="lg:col-span-2">
          <ActivityTimeline
            recent={state.recent}
            github={state.github}
            langfuse={state.langfuse}
            compact
          />
        </div>
      </div>

      {/* Last updated */}
      <div className="text-[10px] text-text-muted text-right">
        Last updated: {state.lastUpdated}
      </div>
    </div>
  );
};

export default React.memo(DashboardPage);
