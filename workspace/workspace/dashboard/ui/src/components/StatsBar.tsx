import React from 'react';
import { Users, CheckCircle, XCircle, Clock, Radio, Zap } from 'lucide-react';
import type { DashboardStats, SystemStatus } from '../types';

interface StatsBarProps {
  stats: DashboardStats;
  system: SystemStatus;
}

interface StatCardProps {
  icon: React.ReactNode;
  label: string;
  value: string | number;
  color: string;
}

const StatCard: React.FC<StatCardProps> = ({ icon, label, value, color }) => (
  <div className="bg-bg-card border border-border-primary rounded-xl px-4 py-3 flex items-center gap-3 min-w-0">
    <div className={`${color} p-2 rounded-lg bg-current/10`} style={{ backgroundColor: 'transparent' }}>
      <div className={color}>{icon}</div>
    </div>
    <div className="min-w-0">
      <div className="text-[11px] text-text-muted uppercase tracking-wider font-medium truncate">
        {label}
      </div>
      <div className="text-xl font-semibold text-text-primary font-mono">{value}</div>
    </div>
  </div>
);

const StatsBar: React.FC<StatsBarProps> = ({ stats, system }) => {
  return (
    <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-6 gap-3">
      <StatCard
        icon={<Users size={16} />}
        label="Active"
        value={stats.totalActive}
        color="text-accent-blue"
      />
      <StatCard
        icon={<CheckCircle size={16} />}
        label="Completed"
        value={stats.completedToday}
        color="text-accent-green"
      />
      <StatCard
        icon={<XCircle size={16} />}
        label="Failed"
        value={stats.failedToday}
        color="text-accent-red"
      />
      <StatCard
        icon={<Clock size={16} />}
        label="Avg Runtime"
        value={`${stats.avgRuntimeMin}m`}
        color="text-accent-purple"
      />
      <StatCard
        icon={<Radio size={16} />}
        label="Gateway"
        value={system.gateway}
        color={system.gateway === 'ok' ? 'text-accent-green' : 'text-accent-red'}
      />
      <StatCard
        icon={<Zap size={16} />}
        label="Queue"
        value={system.queue}
        color={system.queue === 'active' ? 'text-accent-green' : 'text-accent-yellow'}
      />
    </div>
  );
};

export default React.memo(StatsBar);
