export interface LinearData {
  id: string;
  title: string;
  state: string;
  url: string;
  lastComment?: string;
}

export interface ActivityData {
  lastEvent: string;
  lastEventAt: string;
  eventCount: number;
}

export interface EvalProgress {
  completed: number;
  total: number;
  errors: number;
  percent: number;
}

export interface HealthData {
  status: string;
  color: string;
  alert?: string;
}

export interface ActiveAgent {
  sessionKey: string;
  label: string;
  runtimeMs: number;
  status: 'running' | 'eval_running' | 'callback_pending';
  taskId: string;
  pid: number | null;
  source: string;
  role: string | null;
  timeoutMin: number;
  alive: boolean;
  retries: number;
  extensions: number;
  learnings: string[];
  health: HealthData;
  linear: LinearData | null;
  activity: ActivityData | null;
  evalProgress: EvalProgress | null;
  runtimeMin: string;
  etaMin: string;
  progress: string;
}

export interface RecentAgent {
  sessionKey: string;
  label: string;
  runtimeMs: number;
  status: 'done' | 'error';
  taskId: string;
  source: string;
  role: string | null;
  completedAt: string;
  linear: LinearData | null;
  runtimeMin: string;
  success: boolean;
}

export interface SessionToken {
  agent: string;
  model: string;
  used: number;
  total: number;
  percent: number;
}

export interface DashboardStats {
  totalActive: number;
  maxConcurrent: number;
  completedToday: number;
  failedToday: number;
  avgRuntimeMin: string;
  recentTotal: number;
}

export interface SystemStatus {
  gateway: 'ok' | 'down';
  mysql: 'ok' | 'down';
  launchd: 'ok' | 'partial' | 'down';
  launchdCount: number;
  queue: 'active' | 'paused';
}

export interface LangfuseTrace {
  id: string;
  name: string;
  timestamp: string;
  latency: number;
  status: string;
  totalCost: number;
}

export interface LangfuseData {
  totalTraces: number;
  avgLatency: number;
  errorRate: string;
  totalCost: string;
  totalTokens: number;
  recentTraces: LangfuseTrace[];
}

export interface GitHubCommit {
  sha: string;
  message: string;
  author: string;
  date: string;
  repo: string;
  url: string;
}

export interface VMStatus {
  status: 'online' | 'offline' | 'unknown';
  gateway: 'ok' | 'down' | 'unknown';
  uptime?: string;
  lastCheck?: string;
  agent?: string;
}

export interface Alert {
  type: 'warning' | 'error' | 'info';
  message: string;
  timestamp: string;
  sessionKey?: string;
}

export interface ProcessInfo {
  pid: number;
  name: string;
  runtime: string;
  status: string;
}

export interface DashboardState {
  active: ActiveAgent[];
  recent: RecentAgent[];
  stats: DashboardStats;
  alerts: Alert[];
  system: SystemStatus;
  langfuse: LangfuseData | null;
  tokens: SessionToken[];
  processes: ProcessInfo[];
  github: GitHubCommit[];
  remote: VMStatus;
  billy: VMStatus;
  lastUpdated: string;
}

export type Page = 'dashboard' | 'tasks' | 'activity' | 'agent-detail';

export interface NavigationState {
  page: Page;
  selectedAgent?: string;
}

export type WSAction =
  | { action: 'kill'; sessionKey: string }
  | { action: 'refresh' }
  | { action: 'note'; sessionKey: string; message: string };
