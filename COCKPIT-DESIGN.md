# Agent Cockpit — Design System & Specification

## Executive Summary

This document specifies the visual design system and feature set for Anton's Agent Cockpit, aligned with the CreatorAds/Backoffice design language. The goal is to create a professional, production-quality monitoring dashboard that replaces the current cyberpunk-themed prototype with a clean, data-driven interface.

---

## Design System

### Visual Language
**Source**: CreatorAds Backoffice & Creator-ads Frontend (both using shadcn/ui + Radix + Tailwind)

### Color Palette

#### Light Mode (Default)
```css
--background: 0 0% 100%         /* Pure white */
--foreground: 240 10% 3.9%      /* Near black */
--card: 0 0% 100%               /* White cards */
--card-foreground: 240 10% 3.9%
--primary: 240 5.9% 10%         /* Dark gray-blue */
--primary-foreground: 0 0% 98%  /* Off-white */
--secondary: 240 4.8% 95.9%     /* Very light gray */
--secondary-foreground: 240 5.9% 10%
--muted: 240 4.8% 95.9%         /* Light gray */
--muted-foreground: 240 3.8% 46.1% /* Medium gray */
--accent: 240 4.8% 95.9%
--border: 240 5.9% 90%          /* Light border */
--input: 240 5.9% 90%
--radius: 0.75rem               /* 12px rounded corners */
```

#### Chart Colors
```css
--chart-1: 12 76% 61%   /* Orange-red */
--chart-2: 173 58% 39%  /* Teal */
--chart-3: 197 37% 24%  /* Dark teal */
--chart-4: 43 74% 66%   /* Yellow */
--chart-5: 27 87% 67%   /* Orange */
```

#### Dark Mode Support
Full dark mode palette available (same structure, inverted values).

### Typography
- **Font Family**: System font stack (no monospace requirement for production)
  - Primary: `-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial`
  - Code/labels: `"JetBrains Mono"` optional for technical data
- **Scale**:
  - Headings: 1.8rem (h1), 1.2rem (h2), 0.875rem (h3/section labels)
  - Body: 0.875rem (14px) — standard for dashboards
  - Small: 0.75rem (12px) — metadata, timestamps

### Spacing
- **Container**: `2rem` padding, max-width `1400px` (2xl breakpoint)
- **Cards**: `1rem` padding (16px)
- **Grid gaps**: `1rem` standard, `0.75rem` compact
- **Sections**: `1.5rem` margin between major sections

### Components
- **Cards**: `border-radius: 0.75rem`, `border: 1px solid hsl(var(--border))`
- **Buttons**: Radix-based, subtle hover states
- **Progress bars**: Radix Progress component
- **Tooltips**: Radix Tooltip (for truncated labels)
- **Tables**: TanStack Table with zebra striping optional
- **Charts**: Recharts (Area, Bar, Line charts)

### Scrollbars
```css
::-webkit-scrollbar { width: 6px; }
::-webkit-scrollbar-track { background: hsl(var(--muted)); }
::-webkit-scrollbar-thumb { 
  background: hsl(var(--muted-foreground) / 0.2); 
  border-radius: 3px; 
}
::-webkit-scrollbar-thumb:hover { 
  background: hsl(var(--muted-foreground) / 0.4); 
}
```

---

## Dashboard Layout

### Overall Structure
```
┌─────────────────────────────────────────────────────────────────┐
│  [Header: Anton Agent Cockpit 🦞]              [Last: 14:23 UTC]│
│  Real-time orchestration monitoring                             │
├─────────────────────────────────────────────────────────────────┤
│  [Metrics Row: 4 stat cards]                                    │
├─────────────────────────────────────────────────────────────────┤
│  [Active Agents Panel (3-col grid)]   │ [Cost Tracker (1-col)] │
│  ┌─────┐ ┌─────┐ ┌─────┐              │ ┌──────────────────┐   │
│  │Agent│ │Agent│ │Agent│              │ │ Today: $X.XX     │   │
│  │ 1   │ │ 2   │ │ 3   │              │ │ This week: $X.XX │   │
│  └─────┘ └─────┘ └─────┘              │ │ [chart]          │   │
│                                        │ └──────────────────┘   │
├─────────────────────────────────────────────────────────────────┤
│  [Recent Activity Timeline (last 30min)]                        │
│  ✅ Agent X completed in 12m (CAI-42)                           │
│  ⚠️  Agent Y timeout after 25m (CAI-43)                         │
├─────────────────────────────────────────────────────────────────┤
│  [Linear Tasks View]           │ [Slack Activity Feed]          │
│  In Progress (3) │ Blocked (1) │ #tech-gua-ma-internal          │
│  CAI-104 • 15m   │              │ [recent messages]              │
└─────────────────────────────────────────────────────────────────┘
```

### Responsive Breakpoints
- **Desktop (1400px+)**: 4-column metrics, 3-col agent grid, side-by-side panels
- **Tablet (768-1399px)**: 2-column metrics, 2-col agent grid, stacked panels
- **Mobile (<768px)**: Single column, collapsed metrics, stacked cards

---

## Feature Specification

### 1. Metrics Panel (Top Row)

**Layout**: 4 stat cards, horizontal flex, equal width

#### Card 1: Active Agents
- **Value**: Count of running agents (large, bold)
- **Indicator**: Pulse animation when >0
- **Color**: `hsl(var(--primary))`
- **Subtext**: "Currently executing"

#### Card 2: Completed Today
- **Value**: Count of completed agents (last 24h)
- **Indicator**: Checkmark icon
- **Color**: Success green (`173 58% 39%`)
- **Subtext**: "Success rate: XX%"

#### Card 3: Failed/Timeout
- **Value**: Count of failed/timeout agents (last 24h)
- **Indicator**: Warning icon
- **Color**: Destructive red (`0 84.2% 60.2%`)
- **Subtext**: "Needs attention"

#### Card 4: Cost Tracker
- **Value**: Total token cost (today)
- **Indicator**: Dollar sign
- **Color**: `hsl(var(--muted-foreground))`
- **Subtext**: "Today: $X.XX"

---

### 2. Active Agents Panel (Main Content)

**Layout**: Grid of agent cards (3 columns on desktop, responsive)

#### Agent Card Structure
```
┌─────────────────────────────────────────────┐
│ 🟢 Agent Label (CAI-104)        [⋮ Menu]    │
│ ─────────────────────────────────────────── │
│ Task: Implement feature X...                │
│                                             │
│ Runtime: 12m 34s   Model: sonnet-4        │
│ Tokens: 45.2k      Cost: $0.23            │
│                                             │
│ [Progress bar: 60%]                        │
│ Last log: "Analyzing codebase..." (2s ago) │
└─────────────────────────────────────────────┘
```

**Elements**:
- **Status indicator**: Colored dot (green=running, blue=done, red=error)
- **Label**: Agent name + Linear task ID (clickable → opens Linear)
- **Menu**: 3-dot dropdown (steer, kill, view logs)
- **Task**: Truncated description (tooltip on hover)
- **Metadata**: Runtime, model, tokens, cost (2x2 grid)
- **Progress bar**: Radix Progress (estimated based on runtime vs timeout)
- **Last log**: Real-time update from agent (truncated, full text in tooltip)

**States**:
- **Running**: Green dot, animated progress bar
- **Frozen** (>20min): Yellow border, warning icon, "Needs attention" badge
- **Done**: Blue dot, 70% opacity, collapsed view
- **Failed**: Red border, error icon, expandable error details

---

### 3. Cost Tracker Panel (Right Sidebar)

**Layout**: Vertical stack, sticky position

#### Components:
1. **Today's Cost**
   - Large value: `$X.XX`
   - Comparison: `↑ 15% vs yesterday`

2. **Weekly Trend Chart**
   - Recharts Area chart
   - 7-day history
   - X-axis: Days (Mon-Sun)
   - Y-axis: Cost in $

3. **Top Expensive Operations**
   - Mini table (3 rows)
   - Columns: Task, Cost, Tokens
   - Sorted by cost descending

4. **Budget Alert** (conditional)
   - Show if today > threshold
   - Yellow warning banner
   - "Approaching daily budget ($50)"

---

### 4. Recent Activity Timeline

**Layout**: Vertical list, reverse chronological

#### Entry Structure
```
✅ 14:23 UTC — Agent "feature-implementation" completed (12m 34s) • CAI-42
   └─ 45.2k tokens • $0.23 • sonnet-4
```

**Icons by status**:
- ✅ Done (green)
- ⚠️ Timeout (yellow)
- ❌ Failed (red)
- 🚀 Spawned (blue)

**Filters**:
- All / Success / Failed
- Last 30min / 1hr / 6hr / 24hr

**Interactions**:
- Click entry → expand details (logs, full task description)
- Click Linear ID → open in Linear
- Hover → show full timestamps

---

### 5. Linear Tasks Integration

**Layout**: Left column, 50% width

#### Sections:
1. **In Progress** (collapsible)
   - List of tasks with status "In Progress"
   - Each task: `CAI-104 • Agent Cockpit • 15m ago`
   - Click → open Linear task
   - Inline indicator if agent is active

2. **Blocked** (collapsible)
   - Highlighted in yellow
   - Shows tasks needing Caio's attention

3. **Quick Stats**
   - Total tasks this week
   - Avg completion time
   - Backlog count

**Data source**: Linear API (CAI team, caio-tests workspace)

**Update frequency**: Every 30 seconds

---

### 6. Slack Activity Feed

**Layout**: Right column, 50% width, scrollable

#### Components:
1. **Channel selector**
   - Dropdown: `#tech-gua-ma-internal`, `#guardian-alerts`, DMs
   - Default: tech team channel

2. **Message list**
   - Last 20 messages
   - Condensed format:
     ```
     14:23 • caio.fonseca
     Guardian accuracy +3pp with new archetypes
     ```
   - Mentions highlighted (`@Anton`)
   - Links preserved

3. **Quick reply** (optional future feature)
   - Inline text input
   - Send message to channel

**Data source**: Slack API (read-only for now)

**Update frequency**: Every 15 seconds for mentions, 60 seconds otherwise

---

### 7. Alerts & Notifications Panel

**Layout**: Fixed bottom-right toast area

#### Alert Types:
1. **Agent Frozen** (>20min runtime)
   - Yellow toast
   - "Agent 'X' running >20min. Steer or kill?"
   - Actions: [Steer] [Kill] [Dismiss]

2. **Agent Completed**
   - Green toast (brief)
   - "Agent 'X' completed in 12m"
   - Auto-dismiss after 5s

3. **Agent Failed**
   - Red toast (persistent)
   - "Agent 'X' failed: [error message]"
   - Actions: [Retry] [View Logs] [Dismiss]

4. **Budget Warning**
   - Orange toast
   - "Cost today: $X.XX (80% of budget)"

---

### 8. Historical Analytics Panel (Future)

**Layout**: Separate tab or expandable section

#### Charts:
1. **Agent Efficiency Over Time**
   - Line chart: Avg tokens per successful task
   - X-axis: Last 30 days
   - Y-axis: Token count

2. **Completion Rate Trend**
   - Area chart: Success % vs Failed %
   - Stacked areas

3. **Cost by Model**
   - Bar chart: Total cost per model (sonnet, opus, etc.)
   - Last 7 days

4. **Peak Activity Hours**
   - Heatmap: Hour of day vs Day of week
   - Color intensity = agent spawn count

---

## Metrics to Track

### Primary Metrics (Always Visible)
1. **Agent completion rate** (%)
   - Formula: `done / (done + failed + timeout) * 100`
   - Target: >85%

2. **Average task duration** (minutes)
   - Formula: `sum(runtimeMs) / count(completed)`
   - Exclude timeouts

3. **Token cost per task** ($)
   - Formula: `sum(cost) / count(completed)`
   - Model-weighted average

4. **Tasks completed per day**
   - Simple count of `done` status agents
   - Rolling 7-day average

### Secondary Metrics (Expandable Section)
5. **Error/timeout rate** (%)
   - Formula: `(failed + timeout) / total * 100`
   - Alert if >15%

6. **Most expensive operations**
   - Top 5 tasks by token cost
   - Identify optimization targets

7. **Agent efficiency** (tokens per useful output)
   - Manual scoring: "useful" = Caio approval
   - Track over time to measure improvement

8. **Frozen agent rate** (%)
   - Formula: `count(runtime > 20min) / count(active) * 100`
   - Target: <5%

---

## Technical Implementation Notes

### Frontend Stack
- **Framework**: Vanilla HTML/JS (current), or React + Vite (future migration)
- **Styling**: Tailwind CSS 3.4.x
- **Components**: Copy from `/root/.openclaw/workspace/backoffice/src/components/ui/`
  - Button, Card, Progress, Tooltip, Badge
- **Charts**: Recharts 2.x
- **Icons**: Lucide React (or lucide-static for vanilla JS)

### API Endpoints

#### Current (cockpit-server.py)
- `GET /api/agents` → Returns `{active: [], recent: []}`

#### Needed (New)
- `GET /api/metrics/cost?period=day|week|month`
  - Response: `{today: 12.34, thisWeek: 67.89, trend: [...]}`
- `GET /api/linear/tasks?status=inprogress|blocked`
  - Response: `{tasks: [{id, title, status, updatedAt}]}`
- `GET /api/slack/feed?channel=C123&limit=20`
  - Response: `{messages: [{text, user, timestamp}]}`
- `POST /api/agents/:id/steer` (body: `{message: "..."}`)
- `POST /api/agents/:id/kill`

### Data Refresh Strategy
- **Active agents**: Poll every 5 seconds (WebSocket future upgrade)
- **Metrics**: Poll every 30 seconds
- **Linear tasks**: Poll every 60 seconds
- **Slack feed**: Poll every 15 seconds (only if visible)
- **Cost data**: Poll every 5 minutes

### State Management
- Local state (JS objects) for current prototype
- Consider Jotai (same as backoffice) for React migration

---

## Design Patterns from CreatorAds

### 1. Card-Based Grid Layouts
Both backoffice and creator-ads use card grids extensively:
- Consistent `hover:bg-muted/50` interaction
- Subtle borders (`1px solid hsl(var(--border))`)
- Icon + Title + Description pattern
- "Em breve" badges for future features

**Apply to**: Agent cards, metric cards, Linear tasks

### 2. Clean Navigation Hierarchy
- Section titles: `text-xs uppercase tracking-wide text-muted-foreground`
- Breadcrumbs for deep navigation (not needed for cockpit)
- Tab-based views for multi-section pages

**Apply to**: Timeline filters, chart tabs

### 3. Status Indicators
- Colored badges: `inline-flex items-center rounded-full px-2 py-1`
- Icon + text pattern (e.g., `<Brain className="size-5" />`)
- Consistent status colors:
  - Success: `173 58% 39%` (teal)
  - Warning: `43 74% 66%` (yellow)
  - Error: `0 84.2% 60.2%` (red)

**Apply to**: Agent status, task status, alerts

### 4. Data Visualization
- Recharts with custom tooltips
- Muted grid lines
- Subtle area fills (`fill: hsl(var(--primary) / 0.1)`)
- Responsive chart sizing

**Apply to**: Cost trends, efficiency charts

### 5. Loading States
- Skeleton loaders (CSS animation)
- "Loading..." with animated dots
- Graceful error states with retry buttons

**Apply to**: Initial load, API failures

---

## Responsive Design Considerations

### Desktop (1400px+)
- 4-column metric grid
- 3-column agent grid
- Side-by-side Linear + Slack panels
- Full chart visibility

### Tablet (768-1399px)
- 2-column metric grid
- 2-column agent grid
- Stacked Linear/Slack panels
- Condensed charts

### Mobile (<768px)
- Single column layout
- Collapsible sections
- Fixed header with hamburger menu
- Bottom sheet for agent details
- Swipeable timeline cards

---

## Accessibility

1. **ARIA labels**: All interactive elements
2. **Keyboard navigation**: Tab order, focus indicators
3. **Screen reader support**: Semantic HTML, proper heading hierarchy
4. **Color contrast**: WCAG AA minimum (4.5:1 for text)
5. **Motion reduction**: Respect `prefers-reduced-motion`

---

## Future Enhancements (Post-MVP)

1. **WebSocket live updates** (replace polling)
2. **Agent log streaming** (real-time terminal view)
3. **Manual agent spawn** (form UI)
4. **Task assignment** (drag-drop from Linear)
5. **Slack reply integration** (send messages directly)
6. **Cost budget controls** (set limits, auto-pause)
7. **Export reports** (PDF/CSV for weekly summaries)
8. **Dark mode toggle** (full dark theme support)
9. **Multi-user view** (when Anton has collaborators)
10. **Alerting rules** (custom thresholds, email/Slack notifications)

---

## Deliverables

### Phase 1: MVP (This Task)
- [x] Design system documentation (this file)
- [ ] Improved `/tmp/cockpit.html` with CreatorAds design
- [ ] Linear task comments with key findings

### Phase 2: Production (Future)
- [ ] React + Vite migration
- [ ] Component library extraction
- [ ] API server enhancements
- [ ] WebSocket implementation
- [ ] Full Linear/Slack integration

---

## Appendix: Component Mapping

| CreatorAds Component | Cockpit Usage |
|---------------------|---------------|
| `Card` | Agent cards, metric cards |
| `Badge` | Status indicators, tags |
| `Progress` | Agent progress bars |
| `Button` | Actions (steer, kill) |
| `Tooltip` | Truncated text expansion |
| `Tabs` | Timeline filters, chart views |
| `ScrollArea` | Slack feed, activity timeline |
| `DropdownMenu` | Agent actions menu |
| `AlertDialog` | Kill confirmation |

---

**Document Version**: 1.0  
**Last Updated**: 2026-03-06 02:20 UTC  
**Author**: Anton (Subagent CAI-104)  
**Review Status**: Draft → Pending Caio approval
