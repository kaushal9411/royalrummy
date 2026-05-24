import Sidebar from '../../components/layout/sidebar';

export default function AnalyticsLayout({ children }: { children: React.ReactNode }) {
  return (
    <div className="flex min-h-screen bg-dark-bg">
      <Sidebar />
      <main className="flex-1 overflow-auto p-6">{children}</main>
    </div>
  );
}
