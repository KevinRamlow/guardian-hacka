import React from 'react';
import { CheckCircle, XCircle, GitCommit, BarChart3, ExternalLink } from 'lucide-react';
import type { RecentAgent, GitHubCommit, LangfuseData } from '../types';

interface ActivityTimelineProps {
  recent: RecentAgent[];
  github?: GitHubCommit[];
  langfuse?: LangfuseData | null;
  compact?: boolean;
}

function formatTime(dateStr: string): string {
  try {
    const d = new Date(dateStr);
    return d.toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit', hour12: false });
  } catch {
    return dateStr;
  }
}

const ActivityTimeline: React.FC<ActivityTimelineProps> = ({
  recent,
  github = [],
  langfuse,
  compact = false,
}) => {
  const maxItems = compact ? 8 : 50;

  return (
    <div className="bg-bg-card border border-border-primary rounded-xl p-4">
      <h3 className="text-xs uppercase tracking-wider text-text-muted font-medium mb-3">
        Recent Activity
      </h3>

      <div className="space-y-1">
        {recent.slice(0, maxItems).map((agent) => (
          <div
            key={agent.sessionKey}
            className="flex items-center gap-3 py-2 px-2 rounded-lg hover:bg-bg-hover transition-colors"
          >
            {agent.success ? (
              <CheckCircle size={14} className="text-emerald-400 shrink-0" />
            ) : (
              <XCircle size={14} className="text-red-400 shrink-0" />
            )}
            <div className="flex-1 min-w-0">
              <div className="flex items-center gap-2">
                <span className="text-sm text-text-primary truncate">{agent.label}</span>
                {agent.role && (
                  <span className="text-[10px] text-text-muted font-mono">{agent.role}</span>
                )}
              </div>
              {agent.linear && (
                <div className="text-xs text-text-muted truncate">{agent.linear.title}</div>
              )}
            </div>
            <div className="text-right shrink-0">
              <div className="text-xs text-text-muted font-mono">{agent.runtimeMin}m</div>
              <div className="text-[10px] text-text-muted">
                {formatTime(agent.completedAt)}
              </div>
            </div>
          </div>
        ))}

        {/* GitHub commits */}
        {github.slice(0, compact ? 3 : 10).map((commit) => (
          <div
            key={commit.sha}
            className="flex items-center gap-3 py-2 px-2 rounded-lg hover:bg-bg-hover transition-colors"
          >
            <GitCommit size={14} className="text-accent-purple shrink-0" />
            <div className="flex-1 min-w-0">
              <div className="text-sm text-text-primary truncate">
                {commit.message.split('\n')[0]}
              </div>
              <div className="text-[10px] text-text-muted">
                {commit.repo} by {commit.author}
              </div>
            </div>
            <a
              href={commit.url}
              target="_blank"
              rel="noopener noreferrer"
              className="text-text-muted hover:text-text-secondary"
              onClick={(e) => e.stopPropagation()}
            >
              <ExternalLink size={12} />
            </a>
          </div>
        ))}

        {recent.length === 0 && github.length === 0 && (
          <div className="text-sm text-text-muted text-center py-6">No recent activity</div>
        )}
      </div>

      {/* Langfuse summary */}
      {langfuse && !compact && (
        <div className="mt-4 pt-3 border-t border-border-primary">
          <div className="flex items-center gap-2 mb-2">
            <BarChart3 size={14} className="text-accent-cyan" />
            <span className="text-xs text-text-muted uppercase tracking-wider font-medium">
              Langfuse
            </span>
          </div>
          <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
            <LangfuseStat label="Traces" value={String(langfuse.totalTraces)} />
            <LangfuseStat label="Avg Latency" value={`${langfuse.avgLatency.toFixed(1)}s`} />
            <LangfuseStat label="Error Rate" value={langfuse.errorRate} />
            <LangfuseStat label="Cost" value={langfuse.totalCost} />
          </div>
        </div>
      )}
    </div>
  );
};

const LangfuseStat: React.FC<{ label: string; value: string }> = ({ label, value }) => (
  <div>
    <div className="text-[10px] text-text-muted uppercase">{label}</div>
    <div className="text-sm font-mono text-text-primary">{value}</div>
  </div>
);

export default React.memo(ActivityTimeline);
