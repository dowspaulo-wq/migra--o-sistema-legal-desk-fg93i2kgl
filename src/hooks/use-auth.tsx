import { createContext, useContext, useEffect, useState, useRef, ReactNode } from 'react'
import { User, Session } from '@supabase/supabase-js'
import { supabase } from '@/lib/supabase/client'

interface AuthContextType {
  user: User | null
  session: Session | null
  signIn: (email: string, password: string) => Promise<{ error: any }>
  signOut: () => Promise<{ error: any }>
  resetPassword: (email: string) => Promise<{ error: any }>
  updatePassword: (newPassword: string) => Promise<{ error: any }>
  loading: boolean
}

const AuthContext = createContext<AuthContextType | undefined>(undefined)

export const useAuth = () => {
  const context = useContext(AuthContext)
  if (!context) throw new Error('useAuth must be used within an AuthProvider')
  return context
}

const nowISO = () => new Date().toISOString()
const todayDate = () => new Date().toISOString().split('T')[0]

async function createSession(profileId: string): Promise<string | null> {
  const { data, error } = await supabase
    .from('user_sessions')
    .insert({
      profile_id: profileId,
      login_at: nowISO(),
      last_activity_at: nowISO(),
      date: todayDate(),
    })
    .select('id')
    .single()
  if (error) console.error('Failed to create session:', error)
  return data?.id ?? null
}

async function findOpenSession(profileId: string, recentOnly = false): Promise<string | null> {
  let q = supabase
    .from('user_sessions')
    .select('id')
    .eq('profile_id', profileId)
    .is('logout_at', null)
  if (recentOnly) {
    q = q.gte('last_activity_at', new Date(Date.now() - 10 * 60 * 1000).toISOString())
  }
  const { data } = await q.order('last_activity_at', { ascending: false }).limit(1)
  return data?.[0]?.id ?? null
}

async function updateSessionActivity(sessionId: string) {
  await supabase.from('user_sessions').update({ last_activity_at: nowISO() }).eq('id', sessionId)
}

async function closeSession(sessionId: string) {
  await supabase
    .from('user_sessions')
    .update({ logout_at: nowISO(), last_activity_at: nowISO() })
    .eq('id', sessionId)
}

export const AuthProvider = ({ children }: { children: ReactNode }) => {
  const [user, setUser] = useState<User | null>(null)
  const [session, setSession] = useState<Session | null>(null)
  const [loading, setLoading] = useState(true)
  const currentSessionIdRef = useRef<string | null>(null)

  useEffect(() => {
    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange((event, session) => {
      setSession(session)
      setUser(session?.user ?? null)
      setLoading(false)
      if (event === 'SIGNED_OUT' && currentSessionIdRef.current) {
        const sid = currentSessionIdRef.current
        currentSessionIdRef.current = null
        closeSession(sid).then()
      }
    })
    supabase.auth.getSession().then(({ data: { session } }) => {
      setSession(session)
      setUser(session?.user ?? null)
      setLoading(false)
    })
    return () => subscription.unsubscribe()
  }, [])

  useEffect(() => {
    if (!user) {
      currentSessionIdRef.current = null
      return
    }
    const ping = async () => {
      try {
        if (currentSessionIdRef.current) {
          await updateSessionActivity(currentSessionIdRef.current)
          return
        }
        const existing = await findOpenSession(user.id, true)
        if (existing) {
          currentSessionIdRef.current = existing
          await updateSessionActivity(existing)
        } else {
          const newId = await createSession(user.id)
          if (newId) currentSessionIdRef.current = newId
        }
      } catch (error) {
        console.error('Heartbeat ping failed:', error)
      }
    }
    ping()
    const interval = setInterval(ping, 3 * 60 * 1000)
    return () => clearInterval(interval)
  }, [user])

  const signIn = async (email: string, password: string) => {
    const { data, error } = await supabase.auth.signInWithPassword({ email, password })
    if (!error && data.user) {
      const sid = await createSession(data.user.id)
      if (sid) currentSessionIdRef.current = sid
      supabase
        .from('logs')
        .insert({
          action: 'LOGIN',
          entity: 'auth',
          user: data.user.id,
          date: nowISO(),
          details: 'Login realizado',
        })
        .then()
    }
    return { error }
  }

  const signOut = async () => {
    const {
      data: { user },
    } = await supabase.auth.getUser()
    if (user) {
      const sid = currentSessionIdRef.current
      currentSessionIdRef.current = null
      if (sid) {
        await closeSession(sid)
      } else {
        const active = await findOpenSession(user.id)
        if (active) await closeSession(active)
      }
      await supabase.from('logs').insert({
        action: 'LOGOUT',
        entity: 'auth',
        user: user.id,
        date: nowISO(),
        details: 'Logout realizado',
      })
    }
    const { error } = await supabase.auth.signOut()
    return { error }
  }

  const resetPassword = async (email: string) => {
    const { error } = await supabase.auth.resetPasswordForEmail(email, {
      redirectTo: `${window.location.origin}/update-password`,
    })
    return { error }
  }

  const updatePassword = async (newPassword: string) => {
    const { error } = await supabase.auth.updateUser({ password: newPassword })
    return { error }
  }

  return (
    <AuthContext.Provider
      value={{ user, session, signIn, signOut, resetPassword, updatePassword, loading }}
    >
      {children}
    </AuthContext.Provider>
  )
}
