import React, { useEffect, useRef, useState, useCallback } from 'react';
import { Terminal, Copy, Trash2, ArrowDown, Wifi, WifiOff } from 'lucide-react';
import { useSSE } from '../hooks/useSSE';
import type { LogLine } from '../hooks/useSSE';

interface LiveLogViewerProps {
  taskId: string;
}

const typeColors: Record<LogLine['type'], string> = {
  tool: 'text-cyan-400',
  text: 'text-zinc-300',
  meta: 'text-zinc-500',
  error: 'text-red-400',
  task: 'text-amber-400',
  system: 'text-zinc-600',
};

const LiveLogViewer: React.FC<LiveLogViewerProps> = ({ taskId }) => {
  const { lines, connected, clear } = useSSE(taskId);
  const containerRef = useRef<HTMLDivElement>(null);
  const [autoScroll, setAutoScroll] = useState(true);
  const [copied, setCopied] = useState(false);

  // Auto-scroll logic
  useEffect(() => {
    if (autoScroll && containerRef.current) {
      containerRef.current.scrollTop = containerRef.current.scrollHeight;
    }
  }, [lines, autoScroll]);

  const handleScroll = useCallback(() => {
    if (!containerRef.current) return;
    const { scrollTop, scrollHeight, clientHeight } = containerRef.current;
    const atBottom = scrollHeight - scrollTop - clientHeight < 50;
    setAutoScroll(atBottom);
  }, []);

  const scrollToBottom = useCallback(() => {
    if (containerRef.current) {
      containerRef.current.scrollTop = containerRef.current.scrollHeight;
      setAutoScroll(true);
    }
  }, []);

  const copyLogs = useCallback(() => {
    const text = lines.map((l) => `${l.timestamp} ${l.content}`).join('\n');
    navigator.clipboard.writeText(text).then(() => {
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    });
  }, [lines]);

  return (
    <div className="flex flex-col h-full bg-bg-card border border-border-primary rounded-xl overflow-hidden">
      {/* Toolbar */}
      <div className="flex items-center justify-between px-4 py-2 border-b border-border-primary bg-bg-secondary">
        <div className="flex items-center gap-2">
          <Terminal size={14} className="text-text-muted" />
          <span className="text-xs font-mono text-text-secondary">{taskId}</span>
          {connected ? (
            <span className="flex items-center gap-1 text-[10px] text-emerald-400">
              <Wifi size={10} /> live
            </span>
          ) : (
            <span className="flex items-center gap-1 text-[10px] text-red-400">
              <WifiOff size={10} /> disconnected
            </span>
          )}
        </div>
        <div className="flex items-center gap-1">
          <button
            onClick={copyLogs}
            className="p-1.5 rounded hover:bg-bg-hover text-text-muted hover:text-text-secondary transition-colors"
            title="Copy logs"
          >
            <Copy size={12} />
          </button>
          {copied && <span className="text-[10px] text-emerald-400">Copied!</span>}
          <button
            onClick={clear}
            className="p-1.5 rounded hover:bg-bg-hover text-text-muted hover:text-text-secondary transition-colors"
            title="Clear"
          >
            <Trash2 size={12} />
          </button>
          {!autoScroll && (
            <button
              onClick={scrollToBottom}
              className="p-1.5 rounded bg-accent-blue/10 text-accent-blue hover:bg-accent-blue/20 transition-colors"
              title="Scroll to bottom"
            >
              <ArrowDown size={12} />
            </button>
          )}
        </div>
      </div>

      {/* Log output */}
      <div
        ref={containerRef}
        onScroll={handleScroll}
        className="flex-1 overflow-y-auto font-mono text-xs leading-5 p-3 min-h-0"
      >
        {lines.length === 0 && (
          <div className="text-text-muted text-center py-8">
            {connected ? 'Waiting for log output...' : 'Connecting...'}
          </div>
        )}
        {lines.map((line) => (
          <div key={line.id} className="flex hover:bg-white/[0.02] px-1 rounded">
            <span className="text-zinc-600 select-none w-12 shrink-0 text-right pr-3">
              {line.id}
            </span>
            <span className="text-zinc-600 select-none w-20 shrink-0">{line.timestamp}</span>
            <span className={`flex-1 whitespace-pre-wrap break-all ${typeColors[line.type]}`}>
              {line.content}
            </span>
          </div>
        ))}
      </div>

      {/* Status bar */}
      <div className="flex items-center justify-between px-4 py-1.5 border-t border-border-primary bg-bg-secondary text-[10px] text-text-muted">
        <span>{lines.length} lines</span>
        <span>{autoScroll ? 'Auto-scroll ON' : 'Auto-scroll OFF (scroll down to resume)'}</span>
      </div>
    </div>
  );
};

export default React.memo(LiveLogViewer);
