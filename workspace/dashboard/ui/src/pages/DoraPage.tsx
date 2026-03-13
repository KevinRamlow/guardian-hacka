import React, { useEffect, useState } from 'react';
import type { DoraData, DoraHistoryEntry } from '../types';

// ---- Rating helpers ----
const RATING_COLOR: Record<string, string> = {
  elite: 'bg-emerald-500/15 text-emerald-400 border border-emerald-500/20',
  high: 'bg-blue-500/15 text-blue-400 border border-blue-500/20',
  medium: 'bg-amber-500/15 text-amber-400 border border-amber-500/20',
  low: 'bg-red-500/15 text-red-400 border border-red-500/20',
};

const RATING_DOT: Record<string, string> = {
  elite: 'bg-emerald-400',
  high: 'bg-blue-400',
  medium: 'bg-amber-400',
  low: 'bg-red-400',
};

function TrendArrow({ trend }: { trend: string | null }) {
  if (!trend) return <span className="text-text-muted text-xs">—</span>;
  const positive = !trend.startsWith('-');
  return (
    <span className={`text-xs font-mono ${positive ? 'text-emerald-400' : 'text-red-400'}`}>
      {positive ? '↑' : '↓'} {trend}
    </span>
  );
}

interface MetricCardProps {
  title: string;
  description: string;
  value: number | null;
  unit: string;
  trend: string | null;
  rating: string;
  invertTrend?: boolean; // for CFR and lead time: lower is better
}

const MetricCard: React.FC<MetricCardProps> = ({
  title,
  description,
  value,
  unit,
  trend,
  rating,
  invertTrend = false,
}) => {
  // For "lower is better" metrics, invert the color of the trend arrow
  const displayTrend = trend;
  const trendPositive = trend ? !trend.startsWith('-') : null;
  const trendGood = invertTrend
    ? trendPositive === false  // decrease = good
    : trendPositive === true;  // increase = good

  return (
    <div className="bg-bg-card border border-border-primary rounded-xl p-5 space-y-3">
      <div className="flex items-start justify-between">
        <div>
          <div className="text-xs uppercase tracking-wider text-text-muted font-medium">{title}</div>
          <div className="text-[11px] text-text-muted mt-0.5">{description}</div>
        </div>
        <span className={`text-[10px] font-medium px-2 py-0.5 rounded-full capitalize ${RATING_COLOR[rating] || RATING_COLOR.low}`}>
          {rating}
        </span>
      </div>

      <div className="flex items-end gap-3">
        <div className="text-3xl font-bold font-mono text-text-primary">
          {value === null ? 'N/A' : value.toLocaleString()}
        </div>
        {value !== null && (
          <div className="text-sm text-text-muted mb-1">{unit}</div>
        )}
      </div>

      <div className="flex items-center gap-2">
        <span className={`h-1.5 w-1.5 rounded-full ${RATING_DOT[rating] || RATING_DOT.low}`} />
        <span className="text-xs text-text-muted">vs last period:</span>
        {trend ? (
          <span className={`text-xs font-mono ${trendGood ? 'text-emerald-400' : 'text-red-400'}`}>
            {trendPositive ? '↑' : '↓'} {trend}
          </span>
        ) : (
          <span className="text-xs text-text-muted">—</span>
        )}
      </div>
    </div>
  );
};

// ---- SVG Bar Chart ----
interface BarChartProps {
  data: DoraHistoryEntry[];
  days?: number;
}

const BarChart: React.FC<BarChartProps> = ({ data, days = 14 }) => {
  const recent = data.slice(-days);
  if (!recent.length) return <div className="text-text-muted text-sm text-center py-8">No data</div>;

  const W = 600;
  const H = 120;
  const PADDING = { top: 10, right: 10, bottom: 28, left: 30 };
  const chartW = W - PADDING.left - PADDING.right;
  const chartH = H - PADDING.top - PADDING.bottom;

  const maxVal = Math.max(...recent.map(d => d.completed + d.failed), 1);
  const barGroupW = chartW / recent.length;
  const barW = Math.max(4, barGroupW * 0.35);
  const gap = barW * 0.4;

  return (
    <svg
      viewBox={`0 0 ${W} ${H}`}
      className="w-full"
      style={{ maxHeight: 160 }}
    >
      {/* Y-axis grid */}
      {[0, 0.25, 0.5, 0.75, 1].map((frac) => {
        const y = PADDING.top + chartH * (1 - frac);
        return (
          <g key={frac}>
            <line
              x1={PADDING.left}
              x2={PADDING.left + chartW}
              y1={y}
              y2={y}
              stroke="#222"
              strokeWidth={1}
            />
            <text
              x={PADDING.left - 4}
              y={y + 3}
              textAnchor="end"
              fontSize={8}
              fill="#666"
            >
              {Math.round(maxVal * frac)}
            </text>
          </g>
        );
      })}

      {/* Bars */}
      {recent.map((d, i) => {
        const groupX = PADDING.left + i * barGroupW + barGroupW / 2;
        const doneH = (d.completed / maxVal) * chartH;
        const failH = (d.failed / maxVal) * chartH;

        const doneX = groupX - gap / 2 - barW;
        const failX = groupX + gap / 2;

        const shortDate = d.date.substring(5); // MM-DD

        return (
          <g key={d.date}>
            {/* Done bar */}
            <rect
              x={doneX}
              y={PADDING.top + chartH - doneH}
              width={barW}
              height={Math.max(doneH, 0)}
              fill="#22c55e"
              opacity={0.8}
              rx={2}
            >
              <title>{d.date}: {d.completed} completed</title>
            </rect>

            {/* Failed bar */}
            <rect
              x={failX}
              y={PADDING.top + chartH - failH}
              width={barW}
              height={Math.max(failH, 0)}
              fill="#ef4444"
              opacity={0.8}
              rx={2}
            >
              <title>{d.date}: {d.failed} failed</title>
            </rect>

            {/* X label */}
            <text
              x={groupX}
              y={H - PADDING.bottom + 14}
              textAnchor="middle"
              fontSize={7}
              fill="#666"
            >
              {shortDate}
            </text>
          </g>
        );
      })}

      {/* Legend */}
      <rect x={PADDING.left} y={H - 10} width={8} height={6} fill="#22c55e" opacity={0.8} rx={1} />
      <text x={PADDING.left + 11} y={H - 5} fontSize={8} fill="#a0a0a0">Completed</text>
      <rect x={PADDING.left + 75} y={H - 10} width={8} height={6} fill="#ef4444" opacity={0.8} rx={1} />
      <text x={PADDING.left + 88} y={H - 5} fontSize={8} fill="#a0a0a0">Failed</text>
    </svg>
  );
};

// ---- SVG Sparkline for lead time ----
interface SparklineProps {
  data: DoraHistoryEntry[];
  days?: number;
}

const LeadTimeSparkline: React.FC<SparklineProps> = ({ data, days = 14 }) => {
  const recent = data.slice(-days).filter(d => d.avgLeadTime !== null);
  if (recent.length < 2) return <div className="text-text-muted text-sm text-center py-4">Not enough data</div>;

  const W = 600;
  const H = 80;
  const PAD = { top: 8, right: 10, bottom: 20, left: 36 };
  const chartW = W - PAD.left - PAD.right;
  const chartH = H - PAD.top - PAD.bottom;

  const values = recent.map(d => d.avgLeadTime as number);
  const minV = Math.min(...values);
  const maxV = Math.max(...values, minV + 1);

  const scaleX = (i: number) => PAD.left + (i / (recent.length - 1)) * chartW;
  const scaleY = (v: number) => PAD.top + chartH - ((v - minV) / (maxV - minV)) * chartH;

  const points = recent.map((d, i) => `${scaleX(i)},${scaleY(d.avgLeadTime as number)}`).join(' ');
  const areaPoints = [
    `${scaleX(0)},${PAD.top + chartH}`,
    ...recent.map((d, i) => `${scaleX(i)},${scaleY(d.avgLeadTime as number)}`),
    `${scaleX(recent.length - 1)},${PAD.top + chartH}`,
  ].join(' ');

  return (
    <svg viewBox={`0 0 ${W} ${H}`} className="w-full" style={{ maxHeight: 100 }}>
      {/* Y axis labels */}
      <text x={PAD.left - 4} y={PAD.top + 4} textAnchor="end" fontSize={8} fill="#666">{Math.round(maxV)}m</text>
      <text x={PAD.left - 4} y={PAD.top + chartH} textAnchor="end" fontSize={8} fill="#666">{Math.round(minV)}m</text>

      {/* Area fill */}
      <polygon points={areaPoints} fill="#3b82f6" opacity={0.08} />

      {/* Line */}
      <polyline
        points={points}
        fill="none"
        stroke="#3b82f6"
        strokeWidth={1.5}
        strokeLinejoin="round"
        strokeLinecap="round"
      />

      {/* Dots + tooltips */}
      {recent.map((d, i) => (
        <circle key={d.date} cx={scaleX(i)} cy={scaleY(d.avgLeadTime as number)} r={3} fill="#3b82f6">
          <title>{d.date}: {Math.round(d.avgLeadTime as number)} min avg lead time</title>
        </circle>
      ))}

      {/* X labels — show first, mid, last */}
      {[0, Math.floor((recent.length - 1) / 2), recent.length - 1].map(i => (
        <text key={i} x={scaleX(i)} y={H - 4} textAnchor="middle" fontSize={7} fill="#666">
          {recent[i].date.substring(5)}
        </text>
      ))}
    </svg>
  );
};

// ---- Main Page ----
const DoraPage: React.FC = () => {
  const [data, setData] = useState<DoraData | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;

    function load() {
      fetch('/api/dora')
        .then(r => r.json())
        .then(d => {
          if (!cancelled) {
            setData(d);
            setLoading(false);
          }
        })
        .catch(e => {
          if (!cancelled) {
            setError(e.message);
            setLoading(false);
          }
        });
    }

    load();
    const interval = setInterval(load, 60000); // refresh every 60s
    return () => {
      cancelled = true;
      clearInterval(interval);
    };
  }, []);

  if (loading) {
    return (
      <div className="flex items-center justify-center min-h-[40vh]">
        <div className="h-6 w-6 border-2 border-accent-blue/30 border-t-accent-blue rounded-full animate-spin" />
      </div>
    );
  }

  if (error || !data) {
    return (
      <div className="text-red-400 text-sm bg-red-500/5 border border-red-500/10 rounded-xl px-4 py-3">
        Failed to load DORA metrics: {error || 'Unknown error'}
      </div>
    );
  }

  return (
    <div className="space-y-6 animate-fade-in">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-lg font-semibold text-text-primary">DORA Metrics</h1>
          <p className="text-xs text-text-muted mt-0.5">
            DevOps Research &amp; Assessment metrics adapted for Anton (AI orchestrator). Last 30 days.
          </p>
        </div>
        <div className="flex items-center gap-3 text-[10px] text-text-muted">
          <span className="flex items-center gap-1"><span className="h-2 w-2 rounded-full bg-emerald-400" /> Elite</span>
          <span className="flex items-center gap-1"><span className="h-2 w-2 rounded-full bg-blue-400" /> High</span>
          <span className="flex items-center gap-1"><span className="h-2 w-2 rounded-full bg-amber-400" /> Medium</span>
          <span className="flex items-center gap-1"><span className="h-2 w-2 rounded-full bg-red-400" /> Low</span>
        </div>
      </div>

      {/* 4 Metric Cards */}
      <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-4 gap-4">
        <MetricCard
          title="Deployment Frequency"
          description="Completed tasks per day (7-day avg)"
          value={data.deploymentFrequency.value}
          unit={data.deploymentFrequency.unit}
          trend={data.deploymentFrequency.trend}
          rating={data.deploymentFrequency.rating}
        />
        <MetricCard
          title="Lead Time"
          description="Median task creation → completion"
          value={data.leadTime.value}
          unit={data.leadTime.unit}
          trend={data.leadTime.trend}
          rating={data.leadTime.rating}
          invertTrend
        />
        <MetricCard
          title="Change Failure Rate"
          description="% of tasks that failed (last 30 days)"
          value={data.changeFailureRate.value}
          unit={data.changeFailureRate.unit}
          trend={data.changeFailureRate.trend}
          rating={data.changeFailureRate.rating}
          invertTrend
        />
        <MetricCard
          title="MTTR"
          description="Avg time from failure to recovery"
          value={data.mttr.value}
          unit={data.mttr.value !== null ? data.mttr.unit : ''}
          trend={data.mttr.trend}
          rating={data.mttr.rating}
          invertTrend
        />
      </div>

      {/* Charts */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
        {/* Daily completions bar chart */}
        <div className="bg-bg-card border border-border-primary rounded-xl p-5">
          <div className="text-xs uppercase tracking-wider text-text-muted font-medium mb-4">
            Daily Completions vs Failures — Last 14 Days
          </div>
          <BarChart data={data.history} days={14} />
        </div>

        {/* Lead time sparkline */}
        <div className="bg-bg-card border border-border-primary rounded-xl p-5">
          <div className="text-xs uppercase tracking-wider text-text-muted font-medium mb-4">
            Avg Lead Time Trend — Last 14 Days
          </div>
          <LeadTimeSparkline data={data.history} days={14} />
          <div className="mt-3 text-[11px] text-text-muted">
            Median overall: <span className="text-text-secondary font-mono">
              {data.leadTime.value !== null ? `${data.leadTime.value} min` : 'N/A'}
            </span>
          </div>
        </div>
      </div>

      {/* History table */}
      <div className="bg-bg-card border border-border-primary rounded-xl overflow-hidden">
        <div className="px-5 py-3 border-b border-border-primary">
          <div className="text-xs uppercase tracking-wider text-text-muted font-medium">
            Daily History — Last 30 Days
          </div>
        </div>
        <div className="overflow-x-auto">
          <table className="w-full text-xs">
            <thead>
              <tr className="text-text-muted border-b border-border-primary">
                <th className="text-left px-4 py-2 font-medium">Date</th>
                <th className="text-right px-4 py-2 font-medium">Completed</th>
                <th className="text-right px-4 py-2 font-medium">Failed</th>
                <th className="text-right px-4 py-2 font-medium">Failure Rate</th>
                <th className="text-right px-4 py-2 font-medium">Avg Lead Time</th>
              </tr>
            </thead>
            <tbody>
              {[...data.history].reverse().map(d => {
                const total = d.completed + d.failed;
                const rate = total > 0 ? ((d.failed / total) * 100).toFixed(0) : '—';
                return (
                  <tr key={d.date} className="border-b border-border-primary/50 hover:bg-bg-hover transition-colors">
                    <td className="px-4 py-2 font-mono text-text-secondary">{d.date}</td>
                    <td className="px-4 py-2 text-right font-mono text-emerald-400">{d.completed}</td>
                    <td className="px-4 py-2 text-right font-mono text-red-400">{d.failed}</td>
                    <td className="px-4 py-2 text-right font-mono text-text-muted">
                      {total > 0 ? `${rate}%` : '—'}
                    </td>
                    <td className="px-4 py-2 text-right font-mono text-text-muted">
                      {d.avgLeadTime !== null ? `${d.avgLeadTime}m` : '—'}
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
};

export default React.memo(DoraPage);
