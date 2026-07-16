import { useEffect, useRef, useState, type FormEvent } from 'react'
import { Link, useParams } from 'react-router-dom'
import gsap from 'gsap'
import { useGSAP } from '@gsap/react'
import { useAuth } from '../../lib/auth'
import { supabase, type ChatMessage } from '../../lib/supabase'
import { Avatar } from '../../components/Avatar'
import { GlassCard, PageHero } from '../../components/AppUi'

gsap.registerPlugin(useGSAP)

type ConversationRow = {
  id: string
  updated_at: string | null
  job_id: string | null
  worker_id: string | null
  employer_id: string | null
}

type Peer = {
  id: string
  full_name: string | null
  avatar_url: string | null
}

type ConversationView = ConversationRow & { peer: Peer | null }

export function MessagesPage() {
  const { user, isEmployer } = useAuth()
  const [rows, setRows] = useState<ConversationView[]>([])
  const [loading, setLoading] = useState(true)
  const rootRef = useRef<HTMLDivElement>(null)

  useGSAP(
    () => {
      if (loading) return
      gsap.from('.msg-row', {
        opacity: 0,
        x: -12,
        stagger: 0.05,
        duration: 0.4,
        ease: 'power2.out',
      })
    },
    { scope: rootRef, dependencies: [loading, rows.length] },
  )

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

      const list = (data as ConversationRow[]) ?? []
      const enriched = await Promise.all(
        list.map(async (c) => {
          const peerId = isEmployer ? c.worker_id : c.employer_id
          if (!peerId) return { ...c, peer: null }
          const { data: peer } = await supabase
            .from('profiles')
            .select('id, full_name, avatar_url')
            .eq('id', peerId)
            .maybeSingle()
          return { ...c, peer: peer as Peer | null }
        }),
      )
      if (alive) {
        setRows(enriched)
        setLoading(false)
      }
    }

    void load()
    return () => {
      alive = false
    }
  }, [user, isEmployer])

  return (
    <div ref={rootRef}>
      <PageHero
        brush="Inbox"
        title="Messages"
        subtitle="Chat with workers and employers after you apply or hire."
      />
      {loading && <p className="text-white/50">Loading…</p>}
      {!loading && rows.length === 0 && (
        <GlassCard hover={false} className="text-center !py-12">
          <p className="text-white/50">No conversations yet. Apply or hire to start chatting.</p>
        </GlassCard>
      )}
      <div className="grid gap-2">
        {rows.map((c) => {
          const name = c.peer?.full_name ?? 'Conversation'
          return (
            <Link key={c.id} to={`/app/messages/${c.id}`} className="msg-row block">
              <GlassCard className="!py-3">
                <div className="flex items-center gap-2.5 sm:gap-3">
                  <Avatar url={c.peer?.avatar_url} name={name} size="md" />
                  <div className="min-w-0 flex-1">
                    <p className="truncate text-sm font-semibold text-white">{name}</p>
                    <p className="mt-0.5 text-xs text-white/45">
                      Updated {c.updated_at ? new Date(c.updated_at).toLocaleString() : '—'}
                    </p>
                  </div>
                  <span className="text-white/25 transition group-hover:text-paint-soft">→</span>
                </div>
              </GlassCard>
            </Link>
          )
        })}
      </div>
    </div>
  )
}

export function ChatThreadPage() {
  const { id } = useParams()
  const { user, isEmployer } = useAuth()
  const [messages, setMessages] = useState<ChatMessage[]>([])
  const [peer, setPeer] = useState<Peer | null>(null)
  const [text, setText] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const fileRef = useRef<HTMLInputElement>(null)
  const bottomRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    if (!id || !user) return
    let alive = true

    async function loadMeta() {
      const { data: conv } = await supabase
        .from('conversations')
        .select('worker_id, employer_id')
        .eq('id', id!)
        .maybeSingle()
      if (!alive || !conv) return
      const peerId = isEmployer ? conv.worker_id : conv.employer_id
      if (!peerId) return
      const { data } = await supabase
        .from('profiles')
        .select('id, full_name, avatar_url')
        .eq('id', peerId)
        .maybeSingle()
      if (alive) setPeer((data as Peer) ?? null)
    }

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

    void loadMeta()
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
  }, [id, user, isEmployer])

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
    <div className="flex min-h-[65vh] flex-col">
      <Link to="/app/messages" className="mb-3 text-sm text-white/45 hover:text-white sm:mb-4">
        ← Conversations
      </Link>
      <div className="mb-3 flex items-center gap-2.5 sm:mb-4 sm:gap-3">
        <Avatar url={peer?.avatar_url} name={peer?.full_name} size="md" />
        <div>
          <h1 className="font-[family-name:var(--font-display)] text-xl" style={{ fontWeight: 800 }}>
            {peer?.full_name ?? 'Chat'}
          </h1>
          <p className="text-xs text-white/40">Secure Jobsy messages</p>
        </div>
      </div>
      <div className="flex-1 space-y-2.5 overflow-y-auto rounded-[1.25rem] border border-white/8 bg-black/30 p-3 sm:space-y-3 sm:rounded-[1.5rem] sm:p-4 shadow-[inset_0_1px_0_rgba(255,255,255,0.04)]">
        {messages.map((m) => {
          const mine = m.sender_id === user?.id
          const type = m.message_type ?? 'text'
          return (
            <div
              key={m.id}
              className={`max-w-[88%] rounded-2xl px-3 py-2 text-sm shadow-sm sm:max-w-[80%] sm:px-3.5 sm:py-2.5 ${
                mine
                  ? 'ml-auto bg-paint text-white'
                  : 'border border-white/8 bg-white/10 text-white/90'
              }`}
            >
              {type === 'image' && m.attachment_url ? (
                <a href={m.attachment_url} target="_blank" rel="noreferrer">
                  <img
                    src={m.attachment_url}
                    alt="Attachment"
                    className="max-h-48 rounded-xl object-cover sm:max-h-56"
                  />
                </a>
              ) : type === 'file' && m.attachment_url ? (
                <a href={m.attachment_url} target="_blank" rel="noreferrer" className="underline">
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
      <form onSubmit={(e) => void sendText(e)} className="mt-3 flex flex-wrap items-center gap-2">
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
          className="order-3 w-full min-w-0 flex-1 rounded-full border border-white/10 bg-white/5 px-4 py-2.5 text-sm outline-none focus:border-paint/40 focus:ring-2 focus:ring-paint/30 sm:order-none sm:min-w-[12rem]"
        />
        <button
          type="submit"
          disabled={busy}
          className="rounded-full bg-paint px-5 py-2.5 text-sm font-bold disabled:opacity-50"
        >
          Send
        </button>
      </form>
    </div>
  )
}
