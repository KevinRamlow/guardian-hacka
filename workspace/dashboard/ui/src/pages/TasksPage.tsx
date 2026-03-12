import React from 'react';
import TasksTable from '../components/TasksTable';
import type { DashboardState } from '../types';

interface TasksPageProps {
  state: DashboardState;
  onSelectAgent: (sessionKey: string) => void;
}

const TasksPage: React.FC<TasksPageProps> = ({ state, onSelectAgent }) => {
  return (
    <div className="space-y-4 animate-fade-in">
      <div className="flex items-center justify-between">
        <h1 className="text-lg font-semibold text-text-primary">Tasks</h1>
        <div className="text-xs text-text-muted font-mono">
          {state.stats.totalActive} active / {state.stats.completedToday} done / {state.stats.failedToday} failed today
        </div>
      </div>
      <TasksTable
        active={state.active}
        recent={state.recent}
        onSelectAgent={onSelectAgent}
      />
    </div>
  );
};

export default React.memo(TasksPage);
