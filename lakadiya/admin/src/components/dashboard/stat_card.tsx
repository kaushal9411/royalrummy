'use client';
import { useEffect, useState } from 'react';
import AnimatedCounter from './animated_counter';

interface Props {
  label:    string;
  value:    number;
  icon:     string;
  gradient: string;   // e.g. 'from-green-500 to-emerald-700'
  glow:     string;   // e.g. 'rgba(34,197,94,0.25)'
  delay?:   number;   // stagger ms
  suffix?:  string;
}

export default function StatCard({ label, value, icon, gradient, glow, delay = 0, suffix = '' }: Props) {
  const [visible, setVisible] = useState(false);

  useEffect(() => {
    const t = setTimeout(() => setVisible(true), delay);
    return () => clearTimeout(t);
  }, [delay]);

  return (
    <div className={`relative overflow-hidden rounded-2xl p-5 hover-lift cursor-default
                     transition-all duration-300 ${visible ? 'opacity-100 translate-y-0' : 'opacity-0 translate-y-4'}`}
         style={{
           background: `linear-gradient(135deg, var(--c1) 0%, var(--c2) 100%)`,
           boxShadow: `0 8px 32px ${glow}, 0 2px 8px rgba(0,0,0,0.4)`,
           transitionProperty: 'opacity, transform',
         }}>

      {/* Background decorative circle */}
      <div className="absolute -right-6 -top-6 w-24 h-24 rounded-full opacity-20"
           style={{ background: 'rgba(255,255,255,0.3)' }} />
      <div className="absolute -right-2 -bottom-4 w-16 h-16 rounded-full opacity-10"
           style={{ background: 'rgba(255,255,255,0.5)' }} />

      {/* Gradient overlay using className */}
      <div className={`absolute inset-0 rounded-2xl bg-gradient-to-br ${gradient} opacity-90`} />

      {/* Content */}
      <div className="relative z-10">
        <div className="flex items-start justify-between mb-4">
          <div className="w-11 h-11 rounded-xl bg-white/20 flex items-center justify-center text-2xl
                          backdrop-blur-sm shadow-inner">
            {icon}
          </div>
          <div className="w-2 h-2 rounded-full bg-white/60 animate-pulse" />
        </div>

        <p className="text-white/80 text-xs font-semibold uppercase tracking-widest mb-1">
          {label}
        </p>
        <p className="text-white text-3xl font-bold leading-none tracking-tight">
          {visible ? <AnimatedCounter target={value} duration={1000 + delay} /> : '0'}
          {suffix && <span className="text-lg ml-1 opacity-80">{suffix}</span>}
        </p>
      </div>
    </div>
  );
}
