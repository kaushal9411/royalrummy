import { ReactNode } from 'react';
import Link from 'next/link';
import { TrendingUp, TrendingDown } from 'lucide-react';

type Color = 'blue' | 'green' | 'purple' | 'indigo' | 'yellow' | 'red';

const COLOR_MAP: Record<Color, { bg: string; icon: string; badge: string }> = {
  blue:   { bg: 'bg-blue-50',   icon: 'text-blue-600',   badge: 'bg-blue-100 text-blue-700' },
  green:  { bg: 'bg-green-50',  icon: 'text-green-600',  badge: 'bg-green-100 text-green-700' },
  purple: { bg: 'bg-purple-50', icon: 'text-purple-600', badge: 'bg-purple-100 text-purple-700' },
  indigo: { bg: 'bg-indigo-50', icon: 'text-indigo-600', badge: 'bg-indigo-100 text-indigo-700' },
  yellow: { bg: 'bg-yellow-50', icon: 'text-yellow-600', badge: 'bg-yellow-100 text-yellow-700' },
  red:    { bg: 'bg-red-50',    icon: 'text-red-600',    badge: 'bg-red-100 text-red-700' },
};

interface KpiCardProps {
  title: string;
  value?: string;
  change?: string;
  changeType?: 'positive' | 'negative' | 'neutral';
  icon?: ReactNode;
  color?: Color;
  badge?: string;
  alert?: boolean;
  href?: string;
}

export function KpiCard({
  title, value = '—', change, changeType = 'neutral',
  icon, color = 'blue', badge, alert, href,
}: KpiCardProps) {
  const colors = COLOR_MAP[color];

  const card = (
    <div className={`bg-white rounded-xl border border-gray-100 shadow-sm p-5 hover:shadow-md transition-shadow ${alert ? 'ring-2 ring-red-200' : ''}`}>
      <div className="flex items-start justify-between mb-3">
        <p className="text-xs font-medium text-gray-500 uppercase tracking-wide leading-4">{title}</p>
        <div className="flex items-center gap-2">
          {badge && (
            <span className={`text-[10px] font-bold px-1.5 py-0.5 rounded ${colors.badge}`}>
              {badge}
            </span>
          )}
          {icon && (
            <div className={`p-2 rounded-lg ${colors.bg}`}>
              <span className={colors.icon}>{icon}</span>
            </div>
          )}
        </div>
      </div>

      <p className="text-2xl font-bold text-gray-900 mb-2 tabular-nums">{value}</p>

      {change && (
        <div className={`flex items-center gap-1 text-xs font-medium ${
          changeType === 'positive' ? 'text-green-600' :
          changeType === 'negative' ? 'text-red-600' :
          'text-gray-500'
        }`}>
          {changeType === 'positive' ? <TrendingUp className="w-3 h-3" /> :
           changeType === 'negative' ? <TrendingDown className="w-3 h-3" /> : null}
          <span>{change} vs yesterday</span>
        </div>
      )}
    </div>
  );

  return href ? <Link href={href}>{card}</Link> : card;
}
