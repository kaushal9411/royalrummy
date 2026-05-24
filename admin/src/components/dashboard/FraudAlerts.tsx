'use client';

import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { formatDistanceToNow } from 'date-fns';
import { AlertTriangle, CheckCircle2, RefreshCw } from 'lucide-react';
import { api } from '@/utils/api';

interface FraudEvent {
  id: string;
  user_id: string;
  username: string;
  event_type: string;
  severity: 'low' | 'medium' | 'high' | 'critical';
  description: string;
  created_at: string;
}

const SEVERITY_STYLE: Record<string, string> = {
  low:      'bg-yellow-50 text-yellow-700 border-yellow-200',
  medium:   'bg-orange-50 text-orange-700 border-orange-200',
  high:     'bg-red-50 text-red-700 border-red-200',
  critical: 'bg-red-100 text-red-800 border-red-300',
};

export function FraudAlerts() {
  const qc = useQueryClient();

  const { data, isLoading, refetch } = useQuery<{ data: FraudEvent[] }>({
    queryKey: ['fraud-alerts'],
    queryFn: () => api.get('/admin/fraud?resolved=false&limit=8').then(r => r.data),
    refetchInterval: 60_000,
  });

  const resolve = useMutation({
    mutationFn: (id: string) =>
      api.patch(`/admin/fraud/${id}/resolve`, { resolution_notes: 'Resolved from dashboard' }),
    onSuccess: () => qc.invalidateQueries({ queryKey: ['fraud-alerts'] }),
  });

  const events = data?.data || [];

  return (
    <div className="bg-white rounded-xl border border-gray-100 shadow-sm p-5">
      <div className="flex items-center justify-between mb-4">
        <div className="flex items-center gap-2">
          <AlertTriangle className="w-4 h-4 text-red-500" />
          <h3 className="text-sm font-semibold text-gray-800">Fraud Alerts</h3>
          {events.length > 0 && (
            <span className="text-xs font-bold bg-red-100 text-red-700 px-2 py-0.5 rounded-full">
              {events.length}
            </span>
          )}
        </div>
        <button
          onClick={() => refetch()}
          disabled={isLoading}
          className="p-1.5 text-gray-400 hover:text-gray-700 hover:bg-gray-100 rounded-full transition-colors"
        >
          <RefreshCw className={`w-3.5 h-3.5 ${isLoading ? 'animate-spin' : ''}`} />
        </button>
      </div>

      {isLoading ? (
        <div className="space-y-2">
          {[1, 2, 3].map(i => (
            <div key={i} className="h-14 bg-gray-100 rounded-lg animate-pulse" />
          ))}
        </div>
      ) : events.length === 0 ? (
        <div className="flex flex-col items-center gap-2 py-8 text-gray-400">
          <CheckCircle2 className="w-8 h-8 text-green-400" />
          <p className="text-sm">No open fraud alerts</p>
        </div>
      ) : (
        <div className="space-y-2 max-h-72 overflow-y-auto pr-1">
          {events.map(event => (
            <div
              key={event.id}
              className={`flex items-start justify-between gap-3 p-3 rounded-lg border text-xs ${SEVERITY_STYLE[event.severity] || SEVERITY_STYLE.medium}`}
            >
              <div className="flex-1 min-w-0">
                <div className="flex items-center gap-1.5 mb-0.5">
                  <span className="font-bold uppercase text-[10px] tracking-wide">
                    {event.severity}
                  </span>
                  <span className="text-gray-500">·</span>
                  <span className="font-medium truncate">{event.username}</span>
                </div>
                <p className="truncate text-gray-700">{event.event_type}: {event.description}</p>
                <p className="text-gray-400 mt-0.5">
                  {formatDistanceToNow(new Date(event.created_at), { addSuffix: true })}
                </p>
              </div>
              <button
                onClick={() => resolve.mutate(event.id)}
                disabled={resolve.isPending}
                className="shrink-0 p-1 hover:bg-white rounded transition-colors"
                title="Mark resolved"
              >
                <CheckCircle2 className="w-4 h-4" />
              </button>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
