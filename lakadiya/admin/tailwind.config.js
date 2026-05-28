/** @type {import('tailwindcss').Config} */
module.exports = {
  content: [
    './src/pages/**/*.{js,ts,jsx,tsx,mdx}',
    './src/components/**/*.{js,ts,jsx,tsx,mdx}',
    './src/app/**/*.{js,ts,jsx,tsx,mdx}',
  ],
  theme: {
    extend: {
      colors: {
        dark: {
          bg:      '#06080F',
          surface: '#0B0F1A',
          card:    '#0F1420',
          border:  '#1A2235',
          hover:   '#141B2D',
        },
        primary: {
          DEFAULT: '#6366F1',
          dark:    '#4F46E5',
          light:   '#818CF8',
        },
        violet: {
          DEFAULT: '#8B5CF6',
          dark:    '#7C3AED',
          light:   '#A78BFA',
        },
        accent: {
          DEFAULT: '#F59E0B',
          light:   '#FCD34D',
          dark:    '#D97706',
        },
        success: {
          DEFAULT: '#10B981',
          light:   '#34D399',
          dark:    '#059669',
        },
        danger: {
          DEFAULT: '#EF4444',
          light:   '#F87171',
          dark:    '#DC2626',
        },
        warning: {
          DEFAULT: '#F59E0B',
          light:   '#FCD34D',
        },
        info: {
          DEFAULT: '#3B82F6',
          light:   '#60A5FA',
        },
      },
      fontFamily: {
        sans: ['Inter', 'system-ui', '-apple-system', 'sans-serif'],
      },
      backgroundImage: {
        'gradient-primary': 'linear-gradient(135deg, #6366F1 0%, #8B5CF6 100%)',
        'gradient-gold':    'linear-gradient(135deg, #F59E0B 0%, #D97706 100%)',
        'gradient-success': 'linear-gradient(135deg, #10B981 0%, #059669 100%)',
        'gradient-danger':  'linear-gradient(135deg, #EF4444 0%, #DC2626 100%)',
        'gradient-info':    'linear-gradient(135deg, #3B82F6 0%, #2563EB 100%)',
        'gradient-dark':    'linear-gradient(180deg, #06080F 0%, #0B0F1A 100%)',
        'card-glow-primary':'linear-gradient(135deg, rgba(99,102,241,0.15) 0%, rgba(139,92,246,0.05) 100%)',
        'card-glow-gold':   'linear-gradient(135deg, rgba(245,158,11,0.15) 0%, rgba(217,119,6,0.05) 100%)',
        'card-glow-success':'linear-gradient(135deg, rgba(16,185,129,0.15) 0%, rgba(5,150,105,0.05) 100%)',
        'card-glow-danger': 'linear-gradient(135deg, rgba(239,68,68,0.15) 0%, rgba(220,38,38,0.05) 100%)',
      },
      boxShadow: {
        'card':           '0 4px 24px rgba(0,0,0,0.4), 0 1px 0 rgba(255,255,255,0.03)',
        'glow-primary':   '0 0 24px rgba(99,102,241,0.35)',
        'glow-violet':    '0 0 24px rgba(139,92,246,0.35)',
        'glow-gold':      '0 0 24px rgba(245,158,11,0.35)',
        'glow-success':   '0 0 24px rgba(16,185,129,0.35)',
        'glow-danger':    '0 0 24px rgba(239,68,68,0.35)',
        'glow-info':      '0 0 24px rgba(59,130,246,0.35)',
        'inner-glow':     'inset 0 1px 0 rgba(255,255,255,0.06)',
      },
      animation: {
        'fade-in':       'fadeIn 0.4s ease-out',
        'slide-up':      'slideUp 0.4s ease-out',
        'slide-in-left': 'slideInLeft 0.3s ease-out',
        'glow-pulse':    'glowPulse 2s ease-in-out infinite alternate',
        'shimmer':       'shimmer 2s linear infinite',
        'spin-slow':     'spin 3s linear infinite',
        'bounce-subtle': 'bounceSubtle 2s ease-in-out infinite',
        'live-ping':     'livePing 1.5s cubic-bezier(0,0,0.2,1) infinite',
      },
      keyframes: {
        fadeIn: {
          '0%':   { opacity: '0', transform: 'translateY(12px)' },
          '100%': { opacity: '1', transform: 'translateY(0)' },
        },
        slideUp: {
          '0%':   { opacity: '0', transform: 'translateY(20px)' },
          '100%': { opacity: '1', transform: 'translateY(0)' },
        },
        slideInLeft: {
          '0%':   { opacity: '0', transform: 'translateX(-16px)' },
          '100%': { opacity: '1', transform: 'translateX(0)' },
        },
        glowPulse: {
          '0%':   { opacity: '0.6' },
          '100%': { opacity: '1' },
        },
        shimmer: {
          '0%':   { backgroundPosition: '-200% 0' },
          '100%': { backgroundPosition: '200% 0' },
        },
        bounceSubtle: {
          '0%, 100%': { transform: 'translateY(0)' },
          '50%':      { transform: 'translateY(-4px)' },
        },
        livePing: {
          '75%, 100%': { transform: 'scale(2)', opacity: '0' },
        },
      },
    },
  },
  plugins: [],
};
