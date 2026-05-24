'use client';

import {
  AreaChart, Area, XAxis, YAxis, CartesianGrid,
  Tooltip, ResponsiveContainer, Legend,
} from 'recharts';
import { format, parseISO } from 'date-fns';

interface DataPoint {
  date: string;
  revenue: number;
  deposits: number;
}

interface RevenueChartProps {
  data: DataPoint[];
}

const currencyFormatter = (value: number) =>
  value >= 1000 ? `₹${(value / 1000).toFixed(1)}k` : `₹${value}`;

export function RevenueChart({ data }: RevenueChartProps) {
  const formatted = data.map(d => ({
    ...d,
    label: (() => {
      try { return format(parseISO(d.date), 'MMM d'); } catch { return d.date; }
    })(),
  }));

  return (
    <div className="bg-white rounded-xl border border-gray-100 shadow-sm p-5">
      <div className="flex items-center justify-between mb-5">
        <div>
          <h3 className="text-sm font-semibold text-gray-800">Revenue Overview</h3>
          <p className="text-xs text-gray-500 mt-0.5">Last 7 days</p>
        </div>
        <div className="flex items-center gap-4 text-xs">
          <span className="flex items-center gap-1.5">
            <span className="w-2.5 h-2.5 rounded-full bg-yellow-400 inline-block" />
            Entry Fees
          </span>
          <span className="flex items-center gap-1.5">
            <span className="w-2.5 h-2.5 rounded-full bg-blue-400 inline-block" />
            Deposits
          </span>
        </div>
      </div>

      {formatted.length === 0 ? (
        <div className="h-48 flex items-center justify-center text-sm text-gray-400">
          No data yet
        </div>
      ) : (
        <ResponsiveContainer width="100%" height={220}>
          <AreaChart data={formatted} margin={{ top: 4, right: 4, bottom: 0, left: 0 }}>
            <defs>
              <linearGradient id="gradRevenue" x1="0" y1="0" x2="0" y2="1">
                <stop offset="5%" stopColor="#facc15" stopOpacity={0.3} />
                <stop offset="95%" stopColor="#facc15" stopOpacity={0} />
              </linearGradient>
              <linearGradient id="gradDeposits" x1="0" y1="0" x2="0" y2="1">
                <stop offset="5%" stopColor="#60a5fa" stopOpacity={0.3} />
                <stop offset="95%" stopColor="#60a5fa" stopOpacity={0} />
              </linearGradient>
            </defs>
            <CartesianGrid strokeDasharray="3 3" stroke="#f0f0f0" />
            <XAxis dataKey="label" tick={{ fontSize: 11, fill: '#9ca3af' }} axisLine={false} tickLine={false} />
            <YAxis tickFormatter={currencyFormatter} tick={{ fontSize: 11, fill: '#9ca3af' }} axisLine={false} tickLine={false} width={48} />
            <Tooltip
              formatter={(val: number) => `₹${val.toLocaleString()}`}
              contentStyle={{ fontSize: 12, borderRadius: 8, border: '1px solid #e5e7eb' }}
            />
            <Area type="monotone" dataKey="revenue" name="Entry Fees" stroke="#facc15" strokeWidth={2} fill="url(#gradRevenue)" dot={false} />
            <Area type="monotone" dataKey="deposits" name="Deposits" stroke="#60a5fa" strokeWidth={2} fill="url(#gradDeposits)" dot={false} />
          </AreaChart>
        </ResponsiveContainer>
      )}
    </div>
  );
}
