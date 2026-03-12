import { useEffect, useRef, useCallback, useState } from 'react';
import type { DashboardState, WSAction } from '../types';

interface UseWebSocketReturn {
  state: DashboardState | null;
  connected: boolean;
  sendAction: (action: WSAction) => void;
}

const RECONNECT_DELAY = 3000;
const WS_URL = `ws://${window.location.hostname}:8765`;

export function useWebSocket(): UseWebSocketReturn {
  const [state, setState] = useState<DashboardState | null>(null);
  const [connected, setConnected] = useState(false);
  const wsRef = useRef<WebSocket | null>(null);
  const reconnectTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  const connect = useCallback(() => {
    if (wsRef.current?.readyState === WebSocket.OPEN) return;

    const ws = new WebSocket(WS_URL);
    wsRef.current = ws;

    ws.onopen = () => {
      setConnected(true);
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
      reconnectTimerRef.current = setTimeout(connect, RECONNECT_DELAY);
    };

    ws.onerror = () => {
      ws.close();
    };
  }, []);

  useEffect(() => {
    connect();

    // Also fetch initial state via REST
    fetch('/api/state')
      .then((r) => r.json())
      .then((data) => {
        if (data && !state) setState(data);
      })
      .catch(() => {});

    return () => {
      if (reconnectTimerRef.current) clearTimeout(reconnectTimerRef.current);
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
