'use client';
import { useState, useEffect, useRef } from 'react';
import { api } from '../../lib/api';

type Build = {
  id: number;
  version: string;
  build_num: number;
  platform: string;
  filename: string;
  filesize: number;
  notes: string;
  uploaded_by: string;
  created_at: string;
};

const fmt = (bytes: number) => {
  if (bytes >= 1024 * 1024) return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  if (bytes >= 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${bytes} B`;
};

const fmtDate = (d: string) =>
  new Date(d).toLocaleString('en-IN', { dateStyle: 'medium', timeStyle: 'short' });

export default function BuildsPage() {
  const [builds, setBuilds]     = useState<Build[]>([]);
  const [loading, setLoading]   = useState(true);
  const [uploading, setUploading] = useState(false);
  const [showForm, setShowForm] = useState(false);
  const [form, setForm]         = useState({ version: '', build_num: '', notes: '', platform: 'android' });
  const [file, setFile]         = useState<File | null>(null);
  const [error, setError]       = useState('');
  const [success, setSuccess]   = useState('');
  const fileRef = useRef<HTMLInputElement>(null);

  const load = async () => {
    try {
      setLoading(true);
      const { data } = await api.get('/admin/builds');
      setBuilds(data);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => { load(); }, []);

  const upload = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!file) { setError('Please select an APK file'); return; }
    if (!form.version) { setError('Version is required'); return; }
    setError(''); setSuccess('');
    try {
      setUploading(true);
      const fd = new FormData();
      fd.append('apk', file);
      fd.append('version', form.version);
      fd.append('build_num', form.build_num || '0');
      fd.append('notes', form.notes);
      fd.append('platform', form.platform);
      await api.post('/admin/builds/upload', fd, {
        headers: { 'Content-Type': 'multipart/form-data' },
        timeout: 120000,
      });
      setSuccess('Build uploaded successfully');
      setShowForm(false);
      setForm({ version: '', build_num: '', notes: '', platform: 'android' });
      setFile(null);
      if (fileRef.current) fileRef.current.value = '';
      await load();
    } catch (err: any) {
      setError(err.response?.data?.message || 'Upload failed');
    } finally {
      setUploading(false);
    }
  };

  const download = (id: number) => {
    const token = document.cookie.split('; ').find(r => r.startsWith('admin_token='))?.split('=')[1];
    const url = `${process.env.NEXT_PUBLIC_API_URL || 'http://localhost:3001/api'}/admin/builds/${id}/download`;
    const a = document.createElement('a');
    a.href = url;
    a.setAttribute('download', '');
    // Auth via query param since <a> download can't set headers
    a.href = `${url}?token=${token}`;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
  };

  const deleteBuild = async (id: number) => {
    if (!confirm('Delete this build?')) return;
    try {
      await api.delete(`/admin/builds/${id}`);
      setBuilds(b => b.filter(x => x.id !== id));
    } catch {
      setError('Delete failed');
    }
  };

  return (
    <div className="p-6 max-w-5xl mx-auto space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-white">App Builds</h1>
          <p className="text-gray-400 text-sm mt-1">Upload and manage Lakadiya APK releases</p>
        </div>
        <button
          onClick={() => { setShowForm(s => !s); setError(''); setSuccess(''); }}
          className="flex items-center gap-2 px-4 py-2 rounded-xl text-sm font-semibold text-white transition-all"
          style={{ background: 'linear-gradient(135deg,#6366F1,#8B5CF6)' }}
        >
          <span>{showForm ? '✕ Cancel' : '+ Upload Build'}</span>
        </button>
      </div>

      {/* Alerts */}
      {error   && <div className="px-4 py-3 rounded-xl text-sm text-red-300 border border-red-500/30" style={{ background: 'rgba(239,68,68,0.1)' }}>{error}</div>}
      {success && <div className="px-4 py-3 rounded-xl text-sm text-green-300 border border-green-500/30" style={{ background: 'rgba(16,185,129,0.1)' }}>{success}</div>}

      {/* Upload Form */}
      {showForm && (
        <form onSubmit={upload} className="rounded-2xl p-6 space-y-4"
              style={{ background: 'rgba(99,102,241,0.06)', border: '1px solid rgba(99,102,241,0.2)' }}>
          <h2 className="text-white font-semibold text-lg">Upload New Build</h2>
          <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
            <div>
              <label className="text-gray-400 text-xs mb-1 block">Version Name *</label>
              <input
                value={form.version}
                onChange={e => setForm(f => ({ ...f, version: e.target.value }))}
                placeholder="e.g. 1.2.0"
                className="w-full px-3 py-2 rounded-xl text-sm text-white"
                style={{ background: 'rgba(255,255,255,0.05)', border: '1px solid rgba(255,255,255,0.1)' }}
              />
            </div>
            <div>
              <label className="text-gray-400 text-xs mb-1 block">Build Number</label>
              <input
                value={form.build_num}
                onChange={e => setForm(f => ({ ...f, build_num: e.target.value }))}
                placeholder="e.g. 12"
                type="number"
                className="w-full px-3 py-2 rounded-xl text-sm text-white"
                style={{ background: 'rgba(255,255,255,0.05)', border: '1px solid rgba(255,255,255,0.1)' }}
              />
            </div>
            <div>
              <label className="text-gray-400 text-xs mb-1 block">Platform</label>
              <select
                value={form.platform}
                onChange={e => setForm(f => ({ ...f, platform: e.target.value }))}
                className="w-full px-3 py-2 rounded-xl text-sm text-white"
                style={{ background: 'rgba(255,255,255,0.05)', border: '1px solid rgba(255,255,255,0.1)' }}
              >
                <option value="android">Android</option>
                <option value="ios">iOS</option>
              </select>
            </div>
          </div>
          <div>
            <label className="text-gray-400 text-xs mb-1 block">Release Notes</label>
            <textarea
              value={form.notes}
              onChange={e => setForm(f => ({ ...f, notes: e.target.value }))}
              placeholder="What's new in this build..."
              rows={3}
              className="w-full px-3 py-2 rounded-xl text-sm text-white resize-none"
              style={{ background: 'rgba(255,255,255,0.05)', border: '1px solid rgba(255,255,255,0.1)' }}
            />
          </div>
          <div>
            <label className="text-gray-400 text-xs mb-1 block">APK File *</label>
            <input
              ref={fileRef}
              type="file"
              accept=".apk,.aab"
              onChange={e => setFile(e.target.files?.[0] || null)}
              className="w-full text-sm text-gray-300 file:mr-4 file:py-2 file:px-4 file:rounded-xl file:border-0 file:text-sm file:font-semibold file:bg-indigo-600 file:text-white hover:file:bg-indigo-500"
            />
            {file && <p className="text-gray-500 text-xs mt-1">{file.name} — {fmt(file.size)}</p>}
          </div>
          <button
            type="submit"
            disabled={uploading}
            className="px-6 py-2 rounded-xl text-sm font-semibold text-white disabled:opacity-50"
            style={{ background: 'linear-gradient(135deg,#6366F1,#8B5CF6)' }}
          >
            {uploading ? 'Uploading...' : 'Upload Build'}
          </button>
        </form>
      )}

      {/* Builds List */}
      {loading ? (
        <div className="text-center py-16 text-gray-500">Loading...</div>
      ) : builds.length === 0 ? (
        <div className="text-center py-16 rounded-2xl" style={{ border: '1px dashed rgba(255,255,255,0.1)' }}>
          <div className="text-4xl mb-3">📦</div>
          <p className="text-gray-400 font-medium">No builds uploaded yet</p>
          <p className="text-gray-600 text-sm mt-1">Upload your first APK using the button above</p>
        </div>
      ) : (
        <div className="space-y-3">
          {builds.map((b, i) => (
            <div key={b.id}
                 className="flex items-center gap-4 px-5 py-4 rounded-2xl"
                 style={{ background: 'rgba(255,255,255,0.03)', border: `1px solid ${i === 0 ? 'rgba(99,102,241,0.4)' : 'rgba(255,255,255,0.06)'}` }}>
              {/* Badge */}
              <div className="w-10 h-10 rounded-xl flex items-center justify-center flex-shrink-0 text-xl"
                   style={{ background: i === 0 ? 'rgba(99,102,241,0.2)' : 'rgba(255,255,255,0.05)' }}>
                {b.platform === 'android' ? '🤖' : '🍎'}
              </div>

              {/* Info */}
              <div className="flex-1 min-w-0">
                <div className="flex items-center gap-2 flex-wrap">
                  <span className="text-white font-semibold">v{b.version}</span>
                  {b.build_num > 0 && <span className="text-gray-500 text-sm">#{b.build_num}</span>}
                  {i === 0 && (
                    <span className="px-2 py-0.5 rounded-full text-xs font-bold text-indigo-300"
                          style={{ background: 'rgba(99,102,241,0.2)', border: '1px solid rgba(99,102,241,0.4)' }}>
                      Latest
                    </span>
                  )}
                </div>
                {b.notes && <p className="text-gray-400 text-sm mt-0.5 truncate">{b.notes}</p>}
                <p className="text-gray-600 text-xs mt-0.5">
                  {fmt(b.filesize)} · {fmtDate(b.created_at)} · by {b.uploaded_by}
                </p>
              </div>

              {/* Actions */}
              <div className="flex items-center gap-2 flex-shrink-0">
                <button
                  onClick={() => download(b.id)}
                  className="flex items-center gap-1.5 px-3 py-1.5 rounded-xl text-xs font-semibold text-white transition-all hover:opacity-80"
                  style={{ background: 'linear-gradient(135deg,#10B981,#059669)' }}
                >
                  ⬇ Download
                </button>
                <button
                  onClick={() => deleteBuild(b.id)}
                  className="px-3 py-1.5 rounded-xl text-xs font-semibold text-red-400 hover:bg-red-500/10 border border-transparent hover:border-red-500/20 transition-all"
                >
                  🗑
                </button>
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
