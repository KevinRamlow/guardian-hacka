import React, { useState, useMemo } from 'react';
import { AlertTriangle, Filter, ArrowUpDown, Search } from 'lucide-react';
import StatusBadge from './StatusBadge';
import type { ActiveAgent, RecentAgent } from '../types';

interface TaskRow {
  taskId: string;
  sessionKey: string;
  label: string;
  status: string;
  source: string;
  role: string | null;
  runtimeMin: string;
  isZombie: boolean;
  linearTitle: string | null;
  completedAt?: string;
}

interface TasksTableProps {
  active: ActiveAgent[];
  recent: RecentAgent[];
  onSelectAgent: (sessionKey: string) => void;
}

type SortField = 'status' | 'label' | 'runtimeMin' | 'role';
type SortDir = 'asc' | 'desc';

const statusOrder: Record<string, number> = {
  running: 0,
  eval_running: 1,
  callback_pending: 2,
  in_progress: 3,
  todo: 4,
  done: 5,
  error: 6,
  failed: 7,
  zombie: 8,
};

const TasksTable: React.FC<TasksTableProps> = ({ active, recent, onSelectAgent }) => {
  const [statusFilter, setStatusFilter] = useState<string>('all');
  const [searchQuery, setSearchQuery] = useState('');
  const [sortField, setSortField] = useState<SortField>('status');
  const [sortDir, setSortDir] = useState<SortDir>('asc');

  const allTasks: TaskRow[] = useMemo(() => {
    const tasks: TaskRow[] = [];

    for (const a of active) {
      tasks.push({
        taskId: a.taskId,
        sessionKey: a.sessionKey,
        label: a.label,
        status: a.status,
        source: a.source,
        role: a.role,
        runtimeMin: a.runtimeMin,
        isZombie: false,
        linearTitle: a.linear?.title || null,
      });
    }

    for (const r of recent) {
      tasks.push({
        taskId: r.taskId,
        sessionKey: r.sessionKey,
        label: r.label,
        status: r.status === 'done' ? 'done' : 'error',
        source: r.source,
        role: r.role,
        runtimeMin: r.runtimeMin,
        isZombie: false,
        linearTitle: r.linear?.title || null,
        completedAt: r.completedAt,
      });
    }

    return tasks;
  }, [active, recent]);

  const statuses = useMemo(() => {
    const set = new Set(allTasks.map((t) => t.isZombie ? 'zombie' : t.status));
    return ['all', ...Array.from(set).sort((a, b) => (statusOrder[a] ?? 99) - (statusOrder[b] ?? 99))];
  }, [allTasks]);

  const filtered = useMemo(() => {
    let tasks = allTasks;

    if (statusFilter !== 'all') {
      tasks = tasks.filter((t) =>
        statusFilter === 'zombie' ? t.isZombie : t.status === statusFilter
      );
    }

    if (searchQuery) {
      const q = searchQuery.toLowerCase();
      tasks = tasks.filter(
        (t) =>
          t.label.toLowerCase().includes(q) ||
          t.taskId.toLowerCase().includes(q) ||
          (t.linearTitle?.toLowerCase().includes(q)) ||
          (t.role?.toLowerCase().includes(q)) ||
          t.source.toLowerCase().includes(q)
      );
    }

    tasks.sort((a, b) => {
      let cmp = 0;
      switch (sortField) {
        case 'status':
          cmp =
            (statusOrder[a.isZombie ? 'zombie' : a.status] ?? 99) -
            (statusOrder[b.isZombie ? 'zombie' : b.status] ?? 99);
          break;
        case 'label':
          cmp = a.label.localeCompare(b.label);
          break;
        case 'runtimeMin':
          cmp = parseFloat(a.runtimeMin) - parseFloat(b.runtimeMin);
          break;
        case 'role':
          cmp = (a.role || '').localeCompare(b.role || '');
          break;
      }
      return sortDir === 'asc' ? cmp : -cmp;
    });

    return tasks;
  }, [allTasks, statusFilter, searchQuery, sortField, sortDir]);

  const toggleSort = (field: SortField) => {
    if (sortField === field) {
      setSortDir((d) => (d === 'asc' ? 'desc' : 'asc'));
    } else {
      setSortField(field);
      setSortDir('asc');
    }
  };

  return (
    <div className="bg-bg-card border border-border-primary rounded-xl overflow-hidden">
      {/* Toolbar */}
      <div className="flex items-center gap-3 px-4 py-3 border-b border-border-primary">
        <div className="flex items-center gap-2 bg-bg-tertiary rounded-lg px-3 py-1.5 flex-1 max-w-sm">
          <Search size={14} className="text-text-muted" />
          <input
            type="text"
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            placeholder="Search tasks..."
            className="bg-transparent text-sm text-text-primary placeholder-text-muted outline-none flex-1"
          />
        </div>
        <div className="flex items-center gap-1.5">
          <Filter size={12} className="text-text-muted" />
          {statuses.map((s) => (
            <button
              key={s}
              onClick={() => setStatusFilter(s)}
              className={`px-2 py-1 rounded text-xs font-mono transition-colors ${
                statusFilter === s
                  ? 'bg-accent-blue/10 text-accent-blue'
                  : 'text-text-muted hover:text-text-secondary hover:bg-bg-hover'
              }`}
            >
              {s}
            </button>
          ))}
        </div>
      </div>

      {/* Table */}
      <div className="overflow-x-auto">
        <table className="w-full">
          <thead>
            <tr className="text-left text-[10px] text-text-muted uppercase tracking-wider border-b border-border-primary">
              <SortHeader
                label="Status"
                field="status"
                currentField={sortField}
                sortDir={sortDir}
                onToggle={toggleSort}
              />
              <SortHeader
                label="Label"
                field="label"
                currentField={sortField}
                sortDir={sortDir}
                onToggle={toggleSort}
              />
              <th className="px-4 py-2.5">Task ID</th>
              <SortHeader
                label="Role"
                field="role"
                currentField={sortField}
                sortDir={sortDir}
                onToggle={toggleSort}
              />
              <th className="px-4 py-2.5">Source</th>
              <SortHeader
                label="Runtime"
                field="runtimeMin"
                currentField={sortField}
                sortDir={sortDir}
                onToggle={toggleSort}
              />
              <th className="px-4 py-2.5">Linear</th>
            </tr>
          </thead>
          <tbody>
            {filtered.map((task) => (
              <tr
                key={task.sessionKey}
                onClick={() => onSelectAgent(task.sessionKey)}
                className="border-b border-border-primary hover:bg-bg-hover cursor-pointer transition-colors"
              >
                <td className="px-4 py-2.5">
                  <div className="flex items-center gap-1.5">
                    {task.isZombie && (
                      <AlertTriangle size={12} className="text-orange-400" />
                    )}
                    <StatusBadge status={task.isZombie ? 'zombie' : task.status} />
                  </div>
                </td>
                <td className="px-4 py-2.5 text-sm text-text-primary max-w-[200px] truncate">
                  {task.label}
                </td>
                <td className="px-4 py-2.5 text-xs text-text-muted font-mono">{task.taskId}</td>
                <td className="px-4 py-2.5 text-xs text-text-secondary">{task.role || '-'}</td>
                <td className="px-4 py-2.5 text-xs text-text-muted">{task.source}</td>
                <td className="px-4 py-2.5 text-xs text-text-primary font-mono">
                  {task.runtimeMin}m
                </td>
                <td className="px-4 py-2.5 text-xs text-text-secondary max-w-[200px] truncate">
                  {task.linearTitle || '-'}
                </td>
              </tr>
            ))}
            {filtered.length === 0 && (
              <tr>
                <td colSpan={7} className="px-4 py-8 text-sm text-text-muted text-center">
                  No tasks match your filters
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>

      {/* Footer */}
      <div className="px-4 py-2 border-t border-border-primary text-xs text-text-muted">
        {filtered.length} of {allTasks.length} tasks
      </div>
    </div>
  );
};

interface SortHeaderProps {
  label: string;
  field: SortField;
  currentField: SortField;
  sortDir: SortDir;
  onToggle: (field: SortField) => void;
}

const SortHeader: React.FC<SortHeaderProps> = ({ label, field, currentField, sortDir, onToggle }) => (
  <th
    className="px-4 py-2.5 cursor-pointer hover:text-text-secondary transition-colors select-none"
    onClick={() => onToggle(field)}
  >
    <div className="flex items-center gap-1">
      {label}
      <ArrowUpDown
        size={10}
        className={currentField === field ? 'text-accent-blue' : 'text-text-muted'}
      />
      {currentField === field && (
        <span className="text-accent-blue">{sortDir === 'asc' ? '\u2191' : '\u2193'}</span>
      )}
    </div>
  </th>
);

export default React.memo(TasksTable);
