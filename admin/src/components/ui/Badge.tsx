import { ReactNode } from 'react';
import { clsx } from 'clsx';

type Variant = 'green' | 'yellow' | 'red' | 'blue' | 'gray' | 'purple';

const VARIANTS: Record<Variant, string> = {
  green:  'bg-green-100 text-green-700',
  yellow: 'bg-yellow-100 text-yellow-700',
  red:    'bg-red-100 text-red-700',
  blue:   'bg-blue-100 text-blue-700',
  gray:   'bg-gray-100 text-gray-700',
  purple: 'bg-purple-100 text-purple-700',
};

interface BadgeProps {
  children: ReactNode;
  variant?: Variant;
  className?: string;
}

export function Badge({ children, variant = 'gray', className }: BadgeProps) {
  return (
    <span className={clsx('inline-flex items-center px-2 py-0.5 rounded text-xs font-medium', VARIANTS[variant], className)}>
      {children}
    </span>
  );
}
