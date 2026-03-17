import { useEffect, useRef, useCallback, useState } from 'react';
import type { DashboardState, WSAction } from '../types';

interface UseWebSocketReturn {
  state: DashboardState | null;
  connected: boolean;
  sendAction: (action: WSAction) => void;
}

const RECONNECT_DELAY = 3000;
const REST_POLL_INTERVAL = 8000;
const WS_PROTOCOL = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
const WS_URL = `${WS_PROTOCOL}//${window.location.host}`;

export function useWebSocket(): UseWebSocketReturn {
  const [state, setState] = useState<DashboardState | null>(null);
  const [connected, setConnected] = useState(false);
  const wsRef = useRef<WebSocket | null>(null);
  const reconnectTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const pollTimerRef = useRef<ReturnType<typeof setInterval> | null>(null);

  const fetchState = useCallback(() => {
    fetch('/api/state')
      .then((r) => r.json())
      .then((data) => { if (data) setState(data); })
      .catch(() => {});
  }, []);

  const connect = useCallback(() => {
    if (wsRef.current?.readyState === WebSocket.OPEN) return;

    const ws = new WebSocket(WS_URL);
    wsRef.current = ws;

    ws.onopen = () => {
      setConnected(true);
      // Stop REST polling — WS is live
      if (pollTimerRef.current) { clearInterval(pollTimerRef.current); pollTimerRef.current = null; }
    };

    ws.onmessage = (event) => {
      try {
        const msg = JSON.parse(event.data);
        if (msg.type === 'update' && msg.data) {
          setState(msg.data);
        }
      } catch {
        // ignore malformed messages
      }
    };

    ws.onclose = () => {
      setConnected(false);
      wsRef.current = null;
      // Fall back to REST polling while WS is down
      if (!pollTimerRef.current) {
        pollTimerRef.current = setInterval(fetchState, REST_POLL_INTERVAL);
      }
      reconnectTimerRef.current = setTimeout(connect, RECONNECT_DELAY);
    };

    ws.onerror = () => {
      ws.close();
    };
  }, [fetchState]);

  useEffect(() => {
    // Fetch initial state immediately
    fetchState();
    connect();

    return () => {
      if (reconnectTimerRef.current) clearTimeout(reconnectTimerRef.current);
      if (pollTimerRef.current) clearInterval(pollTimerRef.current);
      if (wsRef.current) wsRef.current.close();
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [connect]);

  const sendAction = useCallback((action: WSAction) => {
    if (wsRef.current?.readyState === WebSocket.OPEN) {
      wsRef.current.send(JSON.stringify(action));
    }
  }, []);

  return { state, connected, sendAction };
}
