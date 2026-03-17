import React from 'react';
import ActivityTimeline from '../components/ActivityTimeline';
import type { DashboardState } from '../types';

interface ActivityPageProps {
  state: DashboardState;
}

const ActivityPage: React.FC<ActivityPageProps> = ({ state }) => {
  return (
    <div className="space-y-4 animate-fade-in">
      <h1 className="text-lg font-semibold text-text-primary">Activity</h1>
      <ActivityTimeline
        recent={state.recent}
        github={state.github}
        langfuse={state.langfuse}
      />
    </div>
  );
};

export default React.memo(ActivityPage);
