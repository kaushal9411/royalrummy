interface StatCardProps {
  label: string;
  value: string | number;
  icon:  string;
  color: 'green' | 'blue' | 'yellow' | 'red';
}

const COLOR_MAP = {
  green:  'border-green-500/30 bg-green-500/5',
  blue:   'border-blue-500/30 bg-blue-500/5',
  yellow: 'border-yellow-500/30 bg-yellow-500/5',
  red:    'border-red-500/30 bg-red-500/5',
};

const TEXT_MAP = {
  green:  'text-green-400',
  blue:   'text-blue-400',
  yellow: 'text-yellow-400',
  red:    'text-red-400',
};

export default function StatCard({ label, value, icon, color }: StatCardProps) {
  return (
    <div className={`rounded-xl border p-5 ${COLOR_MAP[color]}`}>
      <div className="flex items-center justify-between mb-3">
        <span className="text-2xl">{icon}</span>
      </div>
      <p className={`text-3xl font-bold ${TEXT_MAP[color]}`}>{value}</p>
      <p className="text-gray-400 text-sm mt-1">{label}</p>
    </div>
  );
}
