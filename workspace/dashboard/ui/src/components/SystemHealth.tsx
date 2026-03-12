import React from 'react';
import { Cpu, Database, Radio, Zap, Server, Globe } from 'lucide-react';
import StatusBadge from './StatusBadge';
import type { SystemStatus, VMStatus } from '../types';

interface SystemHealthProps {
  system: SystemStatus;
  remote: VMStatus;
  billy: VMStatus;
}

interface HealthRowProps {
  icon: React.ReactNode;
  label: string;
  status: string;
  detail?: string;
}

const HealthRow: React.FC<HealthRowProps> = ({ icon, label, status, detail }) => (
  <div className="flex items-center justify-between py-2">
    <div className="flex items-center gap-2.5">
      <span className="text-text-muted">{icon}</span>
      <span className="text-sm text-text-secondary">{label}</span>
      {detail && <span className="text-xs text-text-muted">{detail}</span>}
    </div>
    <StatusBadge status={status} />
  </div>
);

const SystemHealth: React.FC<SystemHealthProps> = ({ system, remote, billy }) => {
  return (
    <div className="bg-bg-card border border-border-primary rounded-xl p-4">
      <h3 className="text-xs uppercase tracking-wider text-text-muted font-medium mb-2">
        System Health
      </h3>
      <div className="divide-y divide-border-primary">
        <HealthRow icon={<Radio size={14} />} label="Gateway" status={system.gateway} />
        <HealthRow icon={<Database size={14} />} label="MySQL" status={system.mysql} />
        <HealthRow
          icon={<Cpu size={14} />}
          label="Launchd"
          status={system.launchd}
          detail={`${system.launchdCount} jobs`}
        />
        <HealthRow icon={<Zap size={14} />} label="Queue" status={system.queue} />
        <HealthRow
          icon={<Server size={14} />}
          label="Son of Anton"
          status={remote?.status || 'unknown'}
        />
        <HealthRow
          icon={<Globe size={14} />}
          label="Billy"
          status={billy?.status || 'unknown'}
        />
      </div>
    </div>
  );
};

export default React.memo(SystemHealth);
