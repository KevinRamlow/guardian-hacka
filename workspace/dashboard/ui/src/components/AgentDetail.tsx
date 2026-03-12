import React, { useState } from 'react';
import {
  ArrowLeft,
  Skull,
  Clock,
  RefreshCw,
  Layers,
  ExternalLink,
  BookOpen,
  MessageSquare,
  Send,
} from 'lucide-react';
import StatusBadge from './StatusBadge';
import LiveLogViewer from './LiveLogViewer';
import type { ActiveAgent, WSAction } from '../types';

interface AgentDetailProps {
  agent: ActiveAgent;
  onBack: () => void;
  sendAction: (action: WSAction) => void;
}

const roleColorMap: Record<string, string> = {
  developer: 'text-role-developer',
  reviewer: 'text-role-reviewer',
  architect: 'text-role-architect',
  'guardian-tuner': 'text-role-guardian',
  guardian: 'text-role-guardian',
  debugger: 'text-role-debugger',
};

const AgentDetail: React.FC<AgentDetailProps> = ({ agent, onBack, sendAction }) => {
  const [showKillConfirm, setShowKillConfirm] = useState(false);
  const [noteText, setNoteText] = useState('');

  const handleKill = () => {
    sendAction({ action: 'kill', sessionKey: agent.sessionKey });
    setShowKillConfirm(false);
    onBack();
  };

  const handleNote = () => {
    if (noteText.trim()) {
      sendAction({ action: 'note', sessionKey: agent.sessionKey, message: noteText.trim() });
      setNoteText('');
    }
  };

  const progressPercent = Math.min(
    100,
    agent.timeoutMin > 0 ? (agent.runtimeMs / (agent.timeoutMin * 60000)) * 100 : 0
  );

  return (
    <div className="flex flex-col h-full gap-4 animate-fade-in">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-3">
          <button
            onClick={onBack}
            className="p-2 rounded-lg hover:bg-bg-hover text-text-muted hover:text-text-primary transition-colors"
          >
            <ArrowLeft size={18} />
          </button>
          <div>
            <div className="flex items-center gap-2">
              <h2 className="text-lg font-semibold text-text-primary">{agent.label}</h2>
              <StatusBadge status={agent.status} size="md" />
            </div>
            <div className="flex items-center gap-3 text-xs text-text-muted mt-0.5">
              <span className="font-mono">{agent.taskId}</span>
              {agent.role && (
                <span className={`font-medium ${roleColorMap[agent.role] || 'text-text-secondary'}`}>
                  {agent.role}
                </span>
              )}
              <span>{agent.source}</span>
            </div>
          </div>
        </div>

        <div className="flex items-center gap-2">
          {!showKillConfirm ? (
            <button
              onClick={() => setShowKillConfirm(true)}
              className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg border border-red-500/20 bg-red-500/5 text-red-400 text-sm hover:bg-red-500/10 transition-colors"
            >
              <Skull size={14} /> Kill
            </button>
          ) : (
            <div className="flex items-center gap-2">
              <span className="text-xs text-red-400">Confirm kill?</span>
              <button
                onClick={handleKill}
                className="px-3 py-1.5 rounded-lg bg-red-500 text-white text-sm font-medium hover:bg-red-600 transition-colors"
              >
                Yes, kill
              </button>
              <button
                onClick={() => setShowKillConfirm(false)}
                className="px-3 py-1.5 rounded-lg border border-border-primary text-text-secondary text-sm hover:bg-bg-hover transition-colors"
              >
                Cancel
              </button>
            </div>
          )}
        </div>
      </div>

      {/* Meta cards row */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
        <MetaCard icon={<Clock size={14} />} label="Runtime" value={`${agent.runtimeMin}m`} />
        <MetaCard icon={<RefreshCw size={14} />} label="Retries" value={String(agent.retries)} />
        <MetaCard icon={<Layers size={14} />} label="Extensions" value={String(agent.extensions)} />
        <MetaCard
          label="Health"
          value={agent.health.status}
          valueColor={
            agent.health.color === 'green'
              ? 'text-emerald-400'
              : agent.health.color === 'red'
              ? 'text-red-400'
              : 'text-amber-400'
          }
        />
      </div>

      {/* Progress */}
      <div className="bg-bg-card border border-border-primary rounded-xl px-4 py-3">
        <div className="flex items-center justify-between text-xs text-text-muted mb-1.5">
          <span>{agent.runtimeMin}m elapsed</span>
          <span>{agent.progress} | ETA {agent.etaMin}m / {agent.timeoutMin}m timeout</span>
        </div>
        <div className="h-2 bg-bg-tertiary rounded-full overflow-hidden">
          <div
            className={`h-full rounded-full transition-all duration-500 ${
              progressPercent < 50
                ? 'bg-emerald-500'
                : progressPercent < 75
                ? 'bg-amber-500'
                : progressPercent < 90
                ? 'bg-orange-500'
                : 'bg-red-500'
            }`}
            style={{ width: `${progressPercent}%` }}
          />
        </div>
      </div>

      {/* Linear + Learnings row */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
        {/* Linear info */}
        {agent.linear && (
          <div className="bg-bg-card border border-border-primary rounded-xl p-4">
            <div className="flex items-center gap-2 mb-2">
              <ExternalLink size={12} className="text-accent-blue" />
              <span className="text-xs text-text-muted uppercase tracking-wider font-medium">
                Linear
              </span>
            </div>
            <div className="text-sm text-text-primary mb-1">{agent.linear.title}</div>
            <div className="text-xs text-text-muted font-mono">{agent.linear.state}</div>
            {agent.linear.lastComment && (
              <div className="mt-2 text-xs text-text-secondary border-l-2 border-border-secondary pl-2 italic">
                {agent.linear.lastComment}
              </div>
            )}
            <a
              href={agent.linear.url}
              target="_blank"
              rel="noopener noreferrer"
              className="mt-2 inline-flex items-center gap-1 text-xs text-accent-blue hover:underline"
            >
              Open in Linear <ExternalLink size={10} />
            </a>
          </div>
        )}

        {/* Learnings */}
        {agent.learnings.length > 0 && (
          <div className="bg-bg-card border border-border-primary rounded-xl p-4">
            <div className="flex items-center gap-2 mb-2">
              <BookOpen size={12} className="text-accent-purple" />
              <span className="text-xs text-text-muted uppercase tracking-wider font-medium">
                Learnings
              </span>
            </div>
            <ul className="space-y-1.5">
              {agent.learnings.map((l, i) => (
                <li key={i} className="text-xs text-text-secondary flex gap-2">
                  <span className="text-text-muted shrink-0">{i + 1}.</span>
                  <span>{l}</span>
                </li>
              ))}
            </ul>
          </div>
        )}
      </div>

      {/* Send note */}
      <div className="bg-bg-card border border-border-primary rounded-xl p-3">
        <div className="flex items-center gap-2">
          <MessageSquare size={12} className="text-text-muted shrink-0" />
          <input
            type="text"
            value={noteText}
            onChange={(e) => setNoteText(e.target.value)}
            onKeyDown={(e) => e.key === 'Enter' && handleNote()}
            placeholder="Send note to agent..."
            className="flex-1 bg-transparent text-sm text-text-primary placeholder-text-muted outline-none"
          />
          <button
            onClick={handleNote}
            disabled={!noteText.trim()}
            className="p-1.5 rounded hover:bg-bg-hover text-text-muted hover:text-accent-blue disabled:opacity-30 transition-colors"
          >
            <Send size={14} />
          </button>
        </div>
      </div>

      {/* Live logs — takes remaining space */}
      <div className="flex-1 min-h-[300px]">
        <LiveLogViewer taskId={agent.taskId} />
      </div>
    </div>
  );
};

interface MetaCardProps {
  icon?: React.ReactNode;
  label: string;
  value: string;
  valueColor?: string;
}

const MetaCard: React.FC<MetaCardProps> = ({ icon, label, value, valueColor = 'text-text-primary' }) => (
  <div className="bg-bg-card border border-border-primary rounded-xl px-3 py-2.5">
    <div className="flex items-center gap-1.5 text-text-muted mb-1">
      {icon}
      <span className="text-[10px] uppercase tracking-wider font-medium">{label}</span>
    </div>
    <div className={`text-lg font-semibold font-mono ${valueColor}`}>{value}</div>
  </div>
);

export default React.memo(AgentDetail);
