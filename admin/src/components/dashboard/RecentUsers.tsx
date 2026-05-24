import Link from 'next/link';
import { formatDistanceToNow } from 'date-fns';
import { CheckCircle, Clock, XCircle } from 'lucide-react';

interface RecentUser {
  id: string;
  username: string;
  phone: string;
  kyc_status: 'pending' | 'approved' | 'rejected';
  created_at: string;
  total_deposited: number;
}

interface RecentUsersProps {
  users: RecentUser[];
}

const KYC_ICON = {
  approved: <CheckCircle className="w-3.5 h-3.5 text-green-500" />,
  pending:  <Clock className="w-3.5 h-3.5 text-yellow-500" />,
  rejected: <XCircle className="w-3.5 h-3.5 text-red-500" />,
};

function maskPhone(phone: string) {
  if (!phone || phone.length < 6) return phone;
  return phone.slice(0, 3) + '*'.repeat(phone.length - 7) + phone.slice(-4);
}

export function RecentUsers({ users }: RecentUsersProps) {
  return (
    <div className="bg-white rounded-xl border border-gray-100 shadow-sm p-5">
      <div className="flex items-center justify-between mb-4">
        <h3 className="text-sm font-semibold text-gray-800">Recent Signups</h3>
        <Link href="/users" className="text-xs text-blue-600 hover:underline font-medium">
          View all
        </Link>
      </div>

      {users.length === 0 ? (
        <p className="text-sm text-gray-400 text-center py-6">No recent signups</p>
      ) : (
        <div className="space-y-1">
          {users.map(user => (
            <Link
              key={user.id}
              href={`/users/${user.id}`}
              className="flex items-center justify-between py-2.5 px-3 rounded-lg hover:bg-gray-50 transition-colors group"
            >
              <div className="flex items-center gap-3">
                <div className="w-8 h-8 rounded-full bg-gray-200 flex items-center justify-center text-xs font-bold text-gray-600 uppercase">
                  {user.username?.[0] || '?'}
                </div>
                <div>
                  <p className="text-sm font-medium text-gray-800 group-hover:text-blue-600 transition-colors">
                    {user.username}
                  </p>
                  <p className="text-xs text-gray-400">{maskPhone(user.phone)}</p>
                </div>
              </div>
              <div className="text-right flex items-center gap-2">
                {KYC_ICON[user.kyc_status] || KYC_ICON.pending}
                <div>
                  <p className="text-xs text-gray-600 font-medium">
                    ₹{parseFloat(user.total_deposited as any || '0').toLocaleString()}
                  </p>
                  <p className="text-[10px] text-gray-400">
                    {formatDistanceToNow(new Date(user.created_at), { addSuffix: true })}
                  </p>
                </div>
              </div>
            </Link>
          ))}
        </div>
      )}
    </div>
  );
}
