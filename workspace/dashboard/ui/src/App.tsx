import React, { useState, useCallback, useMemo } from 'react';
import Sidebar from './components/Sidebar';
import AgentDetail from './components/AgentDetail';
import DashboardPage from './pages/DashboardPage';
import TasksPage from './pages/TasksPage';
import ActivityPage from './pages/ActivityPage';
import { useWebSocket } from './hooks/useWebSocket';
import type { Page, NavigationState } from './types';

const App: React.FC = () => {
  const { state, connected, sendAction } = useWebSocket();
  const [nav, setNav] = useState<NavigationState>({ page: 'dashboard' });
  const [sidebarCollapsed, setSidebarCollapsed] = useState(false);

  const navigate = useCallback((page: Page) => {
    setNav({ page });
  }, []);

  const selectAgent = useCallback((sessionKey: string) => {
    setNav({ page: 'agent-detail', selectedAgent: sessionKey });
  }, []);

  const goBack = useCallback(() => {
    setNav({ page: 'dashboard' });
  }, []);

  const selectedAgent = useMemo(() => {
    if (nav.page !== 'agent-detail' || !nav.selectedAgent || !state) return null;
    return state.active.find((a) => a.sessionKey === nav.selectedAgent) || null;
  }, [nav, state]);

  const sidebarWidth = sidebarCollapsed ? 'pl-16' : 'pl-56';

  return (
    <div className="min-h-screen bg-bg-primary">
      <Sidebar
        currentPage={nav.page === 'agent-detail' ? 'dashboard' : nav.page}
        onNavigate={navigate}
        collapsed={sidebarCollapsed}
        onToggleCollapse={() => setSidebarCollapsed((c) => !c)}
        state={state}
        connected={connected}
      />

      <main className={`${sidebarWidth} transition-all duration-200 min-h-screen`}>
        <div className="max-w-7xl mx-auto px-6 py-6">
          {/* Connection banner */}
          {!connected && (
            <div className="mb-4 bg-red-500/5 border border-red-500/10 rounded-xl px-4 py-3 text-sm text-red-400 flex items-center gap-2">
              <span className="h-2 w-2 rounded-full bg-red-400 animate-pulse-dot" />
              WebSocket disconnected. Attempting to reconnect...
            </div>
          )}

          {/* Loading state */}
          {!state && (
            <div className="flex items-center justify-center min-h-[60vh]">
              <div className="text-center space-y-3">
                <div className="h-8 w-8 border-2 border-accent-blue/30 border-t-accent-blue rounded-full animate-spin mx-auto" />
                <div className="text-sm text-text-muted">Connecting to Anton...</div>
              </div>
            </div>
          )}

          {/* Pages */}
          {state && nav.page === 'dashboard' && (
            <DashboardPage state={state} onSelectAgent={selectAgent} />
          )}

          {state && nav.page === 'agent-detail' && selectedAgent && (
            <AgentDetail agent={selectedAgent} onBack={goBack} sendAction={sendAction} />
          )}

          {state && nav.page === 'agent-detail' && !selectedAgent && (
            <div className="text-center py-12 text-text-muted">
              <div className="text-sm">Agent not found or no longer active.</div>
              <button
                onClick={goBack}
                className="mt-3 text-sm text-accent-blue hover:underline"
              >
                Back to Dashboard
              </button>
            </div>
          )}

          {state && nav.page === 'tasks' && (
            <TasksPage state={state} onSelectAgent={selectAgent} />
          )}

          {state && nav.page === 'activity' && <ActivityPage state={state} />}
        </div>
      </main>
    </div>
  );
};

export default App;
