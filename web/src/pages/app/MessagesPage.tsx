import { useEffect, useRef, useState, type FormEvent } from 'react'
import { Link, useParams } from 'react-router-dom'
import { useAuth } from '../../lib/auth'
import { supabase, type ChatMessage } from '../../lib/supabase'

type ConversationRow = {
  id: string
  updated_at: string | null
  job_id: string | null
  worker_id: string | null
  employer_id: string | null
}

export function MessagesPage() {
  const { user } = useAuth()
  const [rows, setRows] = useState<ConversationRow[]>([])
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    if (!user) return
    let alive = true

    async function load() {
      setLoading(true)
      const { data } = await supabase
        .from('conversations')
        .select('id, updated_at, job_id, worker_id, employer_id')
        .or(`worker_id.eq.${user!.id},employer_id.eq.${user!.id}`)
        .order('updated_at', { ascending: false })
        .limit(40)
      if (alive) {
        setRows((data as ConversationRow[]) ?? [])
        setLoading(false)
      }
    }

    void load()
    return () => {
      alive = false
    }
  }, [user])

  return (
    <div>
      <h1
        className="mb-6 font-[family-name:var(--font-display)] text-3xl tracking-tight"
        style={{ fontWeight: 800 }}
      >
        Messages
      </h1>
      {loading && <p className="text-white/50">Loading…</p>}
      {!loading && rows.length === 0 && (
        <p className="text-white/50">No conversations yet. Apply or hire to start chatting.</p>
      )}
      <div className="grid gap-2">
        {rows.map((c) => (
          <Link
            key={c.id}
            to={`/app/messages/${c.id}`}
            className="rounded-2xl border border-white/8 bg-white/[0.03] px-4 py-3 hover:border-white/20"
          >
            <p className="text-sm font-medium text-white">Conversation</p>
            <p className="mt-1 text-xs text-white/45">
              Updated {c.updated_at ? new Date(c.updated_at).toLocaleString() : '—'}
            </p>
          </Link>
        ))}
      </div>
    </div>
  )
}

export function ChatThreadPage() {
  const { id } = useParams()
  const { user } = useAuth()
  const [messages, setMessages] = useState<ChatMessage[]>([])
  const [text, setText] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const fileRef = useRef<HTMLInputElement>(null)
  const bottomRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    if (!id) return
    let alive = true

    async function load() {
      const { data } = await supabase
        .from('messages')
        .select(
          'id, conversation_id, sender_id, message, message_type, attachment_url, attachment_meta, created_at',
        )
        .eq('conversation_id', id)
        .order('created_at', { ascending: true })
        .limit(200)
      if (alive) {
        setMessages((data as ChatMessage[]) ?? [])
        requestAnimationFrame(() => bottomRef.current?.scrollIntoView({ behavior: 'smooth' }))
      }
    }

    void load()

    const channel = supabase
      .channel(`chat-${id}`)
      .on(
        'postgres_changes',
        {
          event: 'INSERT',
          schema: 'public',
          table: 'messages',
          filter: `conversation_id=eq.${id}`,
        },
        () => void load(),
      )
      .subscribe()

    return () => {
      alive = false
      void supabase.removeChannel(channel)
    }
  }, [id])

  async function sendText(e: FormEvent) {
    e.preventDefault()
    if (!user || !id || !text.trim()) return
    setBusy(true)
    setError(null)
    const { error: err } = await supabase.from('messages').insert({
      conversation_id: id,
      sender_id: user.id,
      message: text.trim(),
      message_type: 'text',
    })
    setBusy(false)
    if (err) {
      setError(err.message)
      return
    }
    setText('')
  }

  async function sendImage(file: File) {
    if (!user || !id) return
    if (file.size > 2 * 1024 * 1024) {
      setError('Image must be under 2 MB')
      return
    }
    setBusy(true)
    setError(null)
    try {
      const ext = file.name.toLowerCase().endsWith('.png') ? 'png' : 'jpg'
      const storagePath = `${id}/${Date.now()}_${user.id.slice(0, 8)}.${ext}`
      const { error: upErr } = await supabase.storage
        .from('chat-attachments')
        .upload(storagePath, file, {
          contentType: file.type || 'image/jpeg',
          upsert: false,
        })
      if (upErr) throw upErr

      const { data: signed, error: signErr } = await supabase.storage
        .from('chat-attachments')
        .createSignedUrl(storagePath, 60 * 60 * 24 * 7)
      if (signErr || !signed?.signedUrl) throw signErr ?? new Error('Could not sign URL')

      const { error: msgErr } = await supabase.from('messages').insert({
        conversation_id: id,
        sender_id: user.id,
        message: null,
        message_type: 'image',
        attachment_url: signed.signedUrl,
        attachment_meta: {
          storage_path: storagePath,
          size: file.size,
          mime: file.type || 'image/jpeg',
        },
      })
      if (msgErr) throw msgErr
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err))
    } finally {
      setBusy(false)
      if (fileRef.current) fileRef.current.value = ''
    }
  }

  async function sendFile(file: File) {
    if (!user || !id) return
    if (file.size > 2 * 1024 * 1024) {
      setError('File must be under 2 MB')
      return
    }
    setBusy(true)
    setError(null)
    try {
      const safe = file.name.replace(/[^a-zA-Z0-9._-]/g, '_')
      const storagePath = `${id}/doc_${Date.now()}_${safe}`
      const { error: upErr } = await supabase.storage
        .from('chat-attachments')
        .upload(storagePath, file, {
          contentType: file.type || 'application/octet-stream',
          upsert: false,
        })
      if (upErr) throw upErr
      const { data: signed, error: signErr } = await supabase.storage
        .from('chat-attachments')
        .createSignedUrl(storagePath, 60 * 60 * 24 * 7)
      if (signErr || !signed?.signedUrl) throw signErr ?? new Error('Could not sign URL')

      const { error: msgErr } = await supabase.from('messages').insert({
        conversation_id: id,
        sender_id: user.id,
        message: null,
        message_type: 'file',
        attachment_url: signed.signedUrl,
        attachment_meta: {
          storage_path: storagePath,
          filename: file.name,
          size: file.size,
          mime: file.type,
        },
      })
      if (msgErr) throw msgErr
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err))
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="flex min-h-[70vh] flex-col">
      <Link to="/app/messages" className="mb-4 text-sm text-white/45 hover:text-white">
        ← Conversations
      </Link>
      <div className="flex-1 space-y-2 overflow-y-auto rounded-2xl border border-white/8 bg-black/20 p-4">
        {messages.map((m) => {
          const mine = m.sender_id === user?.id
          const type = m.message_type ?? 'text'
          return (
            <div
              key={m.id}
              className={`max-w-[80%] rounded-2xl px-3.5 py-2 text-sm ${
                mine ? 'ml-auto bg-[#1e4fd7] text-white' : 'bg-white/10 text-white/90'
              }`}
            >
              {type === 'image' && m.attachment_url ? (
                <a href={m.attachment_url} target="_blank" rel="noreferrer">
                  <img
                    src={m.attachment_url}
                    alt="Attachment"
                    className="max-h-56 rounded-xl object-cover"
                  />
                </a>
              ) : type === 'file' && m.attachment_url ? (
                <a
                  href={m.attachment_url}
                  target="_blank"
                  rel="noreferrer"
                  className="underline"
                >
                  {(m.attachment_meta?.filename as string) || 'Download file'}
                </a>
              ) : (
                m.message
              )}
            </div>
          )
        })}
        <div ref={bottomRef} />
      </div>
      {error && <p className="mt-2 text-sm text-red-400">{error}</p>}
      <form onSubmit={sendText} className="mt-3 flex flex-wrap items-center gap-2">
        <input
          ref={fileRef}
          type="file"
          accept="image/*,.pdf,.doc,.docx,.txt"
          className="hidden"
          onChange={(e) => {
            const file = e.target.files?.[0]
            if (!file) return
            if (file.type.startsWith('image/')) void sendImage(file)
            else void sendFile(file)
          }}
        />
        <button
          type="button"
          disabled={busy}
          onClick={() => fileRef.current?.click()}
          className="rounded-full border border-white/15 px-3 py-2.5 text-xs font-semibold text-white/70 disabled:opacity-50"
        >
          Attach
        </button>
        <input
          value={text}
          onChange={(e) => setText(e.target.value)}
          placeholder="Message…"
          className="min-w-[12rem] flex-1 rounded-full border border-white/10 bg-white/5 px-4 py-2.5 text-sm outline-none focus:ring-2 focus:ring-[#1e4fd7]/50"
        />
        <button
          type="submit"
          disabled={busy}
          className="rounded-full bg-[#1e4fd7] px-5 py-2.5 text-sm font-semibold disabled:opacity-50"
        >
          Send
        </button>
      </form>
    </div>
  )
}
