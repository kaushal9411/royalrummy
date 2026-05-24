import { formatDistanceToNow } from 'date-fns';
import { Users, Zap } from 'lucide-react';

interface LiveTable {
  id: string;
  game_type: string;
  entry_fee: number;
  seated_players: number;
  max_players: number;
  started_at: string | null;
}

interface LiveTablesListProps {
  tables: LiveTable[];
}

const GAME_TYPE_COLOR: Record<string, string> = {
  points: 'bg-blue-100 text-blue-700',
  pool:   'bg-green-100 text-green-700',
  deals:  'bg-purple-100 text-purple-700',
};

export function LiveTablesList({ tables }: LiveTablesListProps) {
  return (
    <div className="bg-white rounded-xl border border-gray-100 shadow-sm p-5 h-full">
      <div className="flex items-center justify-between mb-4">
        <h3 className="text-sm font-semibold text-gray-800">Live Tables</h3>
        <span className="flex items-center gap-1 text-xs text-green-600 font-medium">
          <span className="w-2 h-2 rounded-full bg-green-500 animate-pulse inline-block" />
          {tables.length} active
        </span>
      </div>

      {tables.length === 0 ? (
        <p className="text-sm text-gray-400 text-center py-8">No active tables</p>
      ) : (
        <div className="space-y-2 max-h-72 overflow-y-auto pr-1">
          {tables.map(table => (
            <div key={table.id} className="flex items-center justify-between py-2.5 px-3 rounded-lg bg-gray-50 hover:bg-gray-100 transition-colors">
              <div className="flex items-center gap-2.5">
                <Zap className="w-4 h-4 text-yellow-500 shrink-0" />
                <div>
                  <span className={`text-[10px] font-bold px-1.5 py-0.5 rounded uppercase ${GAME_TYPE_COLOR[table.game_type] || 'bg-gray-100 text-gray-600'}`}>
                    {table.game_type}
                  </span>
                  <p className="text-xs text-gray-500 mt-0.5">
                    {table.started_at
                      ? formatDistanceToNow(new Date(table.started_at), { addSuffix: true })
                      : 'Just started'}
                  </p>
                </div>
              </div>
              <div className="text-right">
                <div className="flex items-center gap-1 text-xs text-gray-700 font-medium">
                  <Users className="w-3 h-3" />
                  {table.seated_players}/{table.max_players}
                </div>
                <p className="text-xs text-green-600 font-semibold">
                  {table.entry_fee > 0 ? `₹${table.entry_fee}` : 'Free'}
                </p>
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
