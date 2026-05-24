import type { Metadata } from 'next';
import './globals.css';

export const metadata: Metadata = {
  title:       'Lakadiya Admin',
  description: 'Admin panel for Lakadiya Callbreak game',
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
