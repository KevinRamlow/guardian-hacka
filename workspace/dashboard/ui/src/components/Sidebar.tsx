import React from 'react';
import {
  LayoutDashboard,
  ListTodo,
  Activity,
  ChevronLeft,
  ChevronRight,
  Cpu,
  Database,
  Radio,
  Zap,
} from 'lucide-react';
import type { Page, DashboardState } from '../types';

interface SidebarProps {
  currentPage: Page;
  onNavigate: (page: Page) => void;
  collapsed: boolean;
  onToggleCollapse: () => void;
  state: DashboardState | null;
  connected: boolean;
}

interface NavItem {
  page: Page;
  label: string;
  icon: React.ReactNode;
  badge?: number;
}

const Sidebar: React.FC<SidebarProps> = ({
  currentPage,
  onNavigate,
  collapsed,
  onToggleCollapse,
  state,
  connected,
}) => {
  const navItems: NavItem[] = [
    {
      page: 'dashboard',
      label: 'Dashboard',
      icon: <LayoutDashboard size={18} />,
      badge: state?.stats.totalActive || undefined,
    },
    {
      page: 'tasks',
      label: 'Tasks',
      icon: <ListTodo size={18} />,
    },
    {
      page: 'activity',
      label: 'Activity',
      icon: <Activity size={18} />,
    },
  ];

  const system = state?.system;

  return (
    <aside
      className={`fixed left-0 top-0 h-screen bg-bg-secondary border-r border-border-primary flex flex-col transition-all duration-200 z-50 ${
        collapsed ? 'w-16' : 'w-56'
      }`}
    >
      {/* Header */}
      <div className="flex items-center justify-between px-4 h-14 border-b border-border-primary">
        {!collapsed && (
          <div className="flex items-center gap-2">
            <div className="h-7 w-7 rounded-lg bg-accent-blue/20 flex items-center justify-center">
              <Zap size={14} className="text-accent-blue" />
            </div>
            <span className="font-semibold text-sm text-text-primary tracking-tight">Anton</span>
          </div>
        )}
        <button
          onClick={onToggleCollapse}
          className="p-1.5 rounded-md hover:bg-bg-hover text-text-muted hover:text-text-secondary transition-colors"
        >
          {collapsed ? <ChevronRight size={16} /> : <ChevronLeft size={16} />}
        </button>
      </div>

      {/* Navigation */}
      <nav className="flex-1 py-3 px-2 space-y-1">
        {navItems.map((item) => {
          const isActive = currentPage === item.page;
          return (
            <button
              key={item.page}
              onClick={() => onNavigate(item.page)}
              className={`w-full flex items-center gap-3 px-3 py-2 rounded-lg text-sm transition-colors ${
                isActive
                  ? 'bg-accent-blue/10 text-accent-blue'
                  : 'text-text-secondary hover:bg-bg-hover hover:text-text-primary'
              }`}
            >
              {item.icon}
              {!collapsed && (
                <>
                  <span className="flex-1 text-left">{item.label}</span>
                  {item.badge !== undefined && item.badge > 0 && (
                    <span className="bg-accent-blue/20 text-accent-blue text-xs font-mono px-1.5 py-0.5 rounded-full">
                      {item.badge}
                    </span>
                  )}
                </>
              )}
              {collapsed && item.badge !== undefined && item.badge > 0 && (
                <span className="absolute left-10 top-0 h-4 w-4 bg-accent-blue text-white text-[10px] flex items-center justify-center rounded-full font-mono">
                  {item.badge}
                </span>
              )}
            </button>
          );
        })}
      </nav>

      {/* System Health */}
      {!collapsed && system && (
        <div className="px-3 pb-4 space-y-2">
          <div className="text-[10px] uppercase tracking-wider text-text-muted font-medium px-1 mb-2">
            System
          </div>
          <SystemIndicator
            icon={<Radio size={12} />}
            label="Gateway"
            status={system.gateway}
          />
          <SystemIndicator
            icon={<Database size={12} />}
            label="MySQL"
            status={system.mysql}
          />
          <SystemIndicator
            icon={<Cpu size={12} />}
            label="Launchd"
            status={system.launchd}
            extra={`(${system.launchdCount})`}
          />
          <SystemIndicator
            icon={<Zap size={12} />}
            label="Queue"
            status={system.queue}
          />
          <div className="pt-2 border-t border-border-primary">
            <div className="flex items-center gap-1.5 px-1">
              <span
                className={`h-1.5 w-1.5 rounded-full ${
                  connected ? 'bg-emerald-400' : 'bg-red-400'
                }`}
              />
              <span className="text-[10px] text-text-muted">
                {connected ? 'Connected' : 'Disconnected'}
              </span>
            </div>
          </div>
        </div>
      )}
    </aside>
  );
};

interface SystemIndicatorProps {
  icon: React.ReactNode;
  label: string;
  status: string;
  extra?: string;
}

const SystemIndicator: React.FC<SystemIndicatorProps> = ({ icon, label, status, extra }) => {
  const colorMap: Record<string, string> = {
    ok: 'text-emerald-400',
    active: 'text-emerald-400',
    down: 'text-red-400',
    partial: 'text-amber-400',
    paused: 'text-amber-400',
  };
  const color = colorMap[status] || 'text-zinc-400';

  return (
    <div className="flex items-center justify-between px-1">
      <div className="flex items-center gap-2 text-text-muted">
        {icon}
        <span className="text-xs">{label}</span>
        {extra && <span className="text-[10px] text-text-muted">{extra}</span>}
      </div>
      <span className={`text-xs font-mono ${color}`}>{status}</span>
    </div>
  );
};

export default React.memo(Sidebar);
