import { type ClassValue, clsx } from 'clsx';
import { twMerge } from 'tailwind-merge';

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

export function formatCurrency(amount: number | string): string {
  const n = typeof amount === 'string' ? parseFloat(amount) : amount;
  if (isNaN(n)) return '₹0';
  return new Intl.NumberFormat('en-IN', {
    style: 'currency',
    currency: 'INR',
    minimumFractionDigits: 0,
    maximumFractionDigits: 2,
  }).format(n);
}

export function formatNumber(n: number | string): string {
  const num = typeof n === 'string' ? parseFloat(n) : n;
  if (isNaN(num)) return '0';
  if (num >= 1_000_000) return `${(num / 1_000_000).toFixed(1)}M`;
  if (num >= 1_000)     return `${(num / 1_000).toFixed(1)}K`;
  return num.toLocaleString('en-IN');
}

export function formatDate(date: string | Date): string {
  const d = typeof date === 'string' ? new Date(date) : date;
  return new Intl.DateTimeFormat('en-IN', {
    day: '2-digit', month: 'short', year: 'numeric',
  }).format(d);
}

export function formatDateTime(date: string | Date): string {
  const d = typeof date === 'string' ? new Date(date) : date;
  return new Intl.DateTimeFormat('en-IN', {
    day: '2-digit', month: 'short', year: 'numeric',
    hour: '2-digit', minute: '2-digit', hour12: true,
  }).format(d);
}

export function timeAgo(date: string | Date): string {
  const d    = typeof date === 'string' ? new Date(date) : date;
  const diff = Math.floor((Date.now() - d.getTime()) / 1000);
  if (diff < 60)   return `${diff}s ago`;
  if (diff < 3600) return `${Math.floor(diff / 60)}m ago`;
  if (diff < 86400)return `${Math.floor(diff / 3600)}h ago`;
  return `${Math.floor(diff / 86400)}d ago`;
}

export function truncate(str: string, maxLen = 20): string {
  return str.length > maxLen ? str.slice(0, maxLen) + '…' : str;
}

export function getStatusColor(status: string): string {
  const map: Record<string, string> = {
    active:    'text-success-light bg-success/10 border-success/20',
    completed: 'text-info-light bg-info/10 border-info/20',
    pending:   'text-accent-light bg-accent/10 border-accent/20',
    success:   'text-success-light bg-success/10 border-success/20',
    failed:    'text-danger-light bg-danger/10 border-danger/20',
    rejected:  'text-danger-light bg-danger/10 border-danger/20',
    approved:  'text-success-light bg-success/10 border-success/20',
    banned:    'text-danger-light bg-danger/10 border-danger/20',
    waiting:   'text-violet-light bg-violet/10 border-violet/20',
    playing:   'text-primary-light bg-primary/10 border-primary/20',
    finished:  'text-dark-border bg-dark-border/10 border-dark-border/20',
  };
  return map[status?.toLowerCase()] ?? 'text-gray-400 bg-gray-400/10 border-gray-400/20';
}
