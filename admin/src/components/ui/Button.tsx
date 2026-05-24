import { ReactNode, ButtonHTMLAttributes } from 'react';
import { clsx } from 'clsx';

type Variant = 'primary' | 'secondary' | 'danger' | 'ghost';
type Size = 'sm' | 'md' | 'lg';

const VARIANT_STYLES: Record<Variant, string> = {
  primary:   'bg-yellow-400 text-gray-900 hover:bg-yellow-500 font-semibold',
  secondary: 'bg-white text-gray-700 border border-gray-300 hover:bg-gray-50',
  danger:    'bg-red-600 text-white hover:bg-red-700 font-semibold',
  ghost:     'text-gray-600 hover:bg-gray-100',
};

const SIZE_STYLES: Record<Size, string> = {
  sm: 'px-3 py-1.5 text-xs',
  md: 'px-4 py-2 text-sm',
  lg: 'px-6 py-3 text-base',
};

interface ButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  children: ReactNode;
  variant?: Variant;
  size?: Size;
  loading?: boolean;
  icon?: ReactNode;
}

export function Button({
  children, variant = 'secondary', size = 'md',
  loading, icon, className, disabled, ...props
}: ButtonProps) {
  return (
    <button
      {...props}
      disabled={disabled || loading}
      className={clsx(
        'inline-flex items-center gap-2 rounded-lg transition-colors focus:outline-none focus:ring-2 focus:ring-yellow-400 focus:ring-offset-1',
        VARIANT_STYLES[variant],
        SIZE_STYLES[size],
        (disabled || loading) && 'opacity-50 cursor-not-allowed',
        className
      )}
    >
      {loading ? (
        <svg className="w-4 h-4 animate-spin" viewBox="0 0 24 24" fill="none">
          <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" />
          <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8v8H4z" />
        </svg>
      ) : icon}
      {children}
    </button>
  );
}
