import { useEffect, useRef, useState, useCallback } from 'react';

export interface LogLine {
  id: number;
  timestamp: string;
  type: 'tool' | 'text' | 'meta' | 'error' | 'task' | 'system';
  content: string;
  raw: string;
}

interface UseSSEReturn {
  lines: LogLine[];
  connected: boolean;
  clear: () => void;
}

let lineCounter = 0;

function classifyLine(text: string): LogLine['type'] {
  if (/\[tool\]/i.test(text) || /Tool (?:call|result|use)/i.test(text)) return 'tool';
  if (/\[error\]/i.test(text) || /error|exception|failed|panic/i.test(text)) return 'error';
  if (/\[task\]/i.test(text) || /\[spawn\]/i.test(text) || /task[_-]?id/i.test(text)) return 'task';
  if (/\[meta\]/i.test(text) || /\[system\]/i.test(text) || /session|token|model/i.test(text)) return 'meta';
  return 'text';
}

function parseLine(raw: string): LogLine {
  const now = new Date().toLocaleTimeString('en-US', { hour12: false });
  return {
    id: ++lineCounter,
    timestamp: now,
    type: classifyLine(raw),
    content: raw,
    raw,
  };
}

export function useSSE(taskId: string | null): UseSSEReturn {
  const [lines, setLines] = useState<LogLine[]>([]);
  const [connected, setConnected] = useState(false);
  const sourceRef = useRef<EventSource | null>(null);

  const clear = useCallback(() => setLines([]), []);

  useEffect(() => {
    if (!taskId) {
      setConnected(false);
      return;
    }

    setLines([]);
    const es = new EventSource(`/api/stream/${taskId}`);
    sourceRef.current = es;

    es.onopen = () => setConnected(true);

    es.onmessage = (event) => {
      const line = parseLine(event.data);
      setLines((prev) => {
        const next = [...prev, line];
        // Keep last 2000 lines to prevent memory bloat
        return next.length > 2000 ? next.slice(-1500) : next;
      });
    };

    es.onerror = () => {
      setConnected(false);
      es.close();
    };

    return () => {
      es.close();
      sourceRef.current = null;
      setConnected(false);
    };
  }, [taskId]);

  return { lines, connected, clear };
}
