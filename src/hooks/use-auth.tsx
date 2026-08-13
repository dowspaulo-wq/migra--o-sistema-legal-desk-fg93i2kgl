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

const getLocalDateString = () => {
  const now = new Date()
  const year = now.getFullYear()
  const month = String(now.getMonth() + 1).padStart(2, '0')
  const day = String(now.getDate()).padStart(2, '0')
  return `${year}-${month}-${day}`
}

async function createSession(profileId: string): Promise<string | null> {
  const { data, error } = await supabase
    .from('user_sessions')
    .insert({
      profile_id: profileId,
      login_at: nowISO(),
      last_activity_at: nowISO(),
      date: getLocalDateString(),
    })
    .select('id')
    .single()
  if (error) console.error('Failed to create session:', error)
  return data?.id ?? null
}

async function findOpenSession(profileId: string): Promise<string | null> {
  const { data } = await supabase
    .from('user_sessions')
    .select('id')
    .eq('profile_id', profileId)
    .is('logout_at', null)
    .order('login_at', { ascending: false })
    .limit(1)
  return data?.[0]?.id ?? null
}

async function closeSession(sessionId: string) {
  await supabase
    .from('user_sessions')
    .update({ logout_at: nowISO(), last_activity_at: nowISO() })
    .eq('id', sessionId)
    .is('logout_at', null)
}

async function closeAllOpenSessions(profileId: string): Promise<void> {
  const { data } = await supabase
    .from('user_sessions')
    .select('id, last_activity_at, login_at')
    .eq('profile_id', profileId)
    .is('logout_at', null)
  if (data && data.length > 0) {
    for (const session of data) {
      const computedLogout = session.last_activity_at || session.login_at || nowISO()
      await supabase
        .from('user_sessions')
        .update({ logout_at: computedLogout })
        .eq('id', session.id)
        .is('logout_at', null)
    }
  }
}

export const AuthProvider = ({ children }: { children: ReactNode }) => {
  const [user, setUser] = useState<User | null>(null)
  const [session, setSession] = useState<Session | null>(null)
  const [loading, setLoading] = useState(true)
  const currentSessionIdRef = useRef<string | null>(null)
  const sessionPromiseRef = useRef<Promise<string | null> | null>(null)

  const startNewSession = async (profileId: string): Promise<string | null> => {
    if (sessionPromiseRef.current) {
      return sessionPromiseRef.current
    }

    sessionPromiseRef.current = (async () => {
      try {
        // Always close any previously open session for this profile so each
        // login produces its own distinct row in user_sessions (Acessos).
        await closeAllOpenSessions(profileId)

        const newId = await createSession(profileId)
        if (newId) {
          currentSessionIdRef.current = newId
        }
        return newId
      } catch (err) {
        console.error('Error starting new session:', err)
        return null
      } finally {
        sessionPromiseRef.current = null
      }
    })()

    return sessionPromiseRef.current
  }

  const ensureActiveSession = async (profileId: string): Promise<string | null> => {
    // Check if there are any old stale open sessions (older than 15 min without activity or from another day)
    const { data: staleSessions } = await supabase
      .from('user_sessions')
      .select('id, last_activity_at, login_at, date')
      .eq('profile_id', profileId)
      .is('logout_at', null)

    const todayStr = getLocalDateString()
    const nowMs = Date.now()

    if (staleSessions && staleSessions.length > 0) {
      for (const s of staleSessions) {
        const lastActiveMs = s.last_activity_at ? new Date(s.last_activity_at).getTime() : 0
        const isStale =
          s.date !== todayStr || (lastActiveMs > 0 && nowMs - lastActiveMs > 15 * 60 * 1000)

        if (isStale) {
          const computedLogout = s.last_activity_at || s.login_at || nowISO()
          await supabase
            .from('user_sessions')
            .update({ logout_at: computedLogout })
            .eq('id', s.id)
            .is('logout_at', null)

          if (currentSessionIdRef.current === s.id) {
            currentSessionIdRef.current = null
          }
        }
      }
    }

    if (currentSessionIdRef.current) {
      const { count } = await supabase
        .from('user_sessions')
        .update({ last_activity_at: nowISO() }, { count: 'exact' })
        .eq('id', currentSessionIdRef.current)
        .is('logout_at', null)
      if (count && count > 0) {
        return currentSessionIdRef.current
      }
      currentSessionIdRef.current = null
      return startNewSession(profileId)
    }

    const existing = await findOpenSession(profileId)
    if (existing) {
      currentSessionIdRef.current = existing
      await supabase
        .from('user_sessions')
        .update({ last_activity_at: nowISO() })
        .eq('id', existing)
        .is('logout_at', null)
      return existing
    }

    return startNewSession(profileId)
  }

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
        sessionPromiseRef.current = null
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
      sessionPromiseRef.current = null
      return
    }

    const ping = async () => {
      try {
        await ensureActiveSession(user.id)
      } catch (error) {
        console.error('Heartbeat ping failed:', error)
      }
    }

    ping()
    const interval = setInterval(ping, 2 * 60 * 1000)

    const handleBeforeUnload = () => {
      if (currentSessionIdRef.current) {
        const sid = currentSessionIdRef.current
        const timeStr = nowISO()
        // Try close via Beacon or sync request if possible
        const body = JSON.stringify({ logout_at: timeStr })
        const blob = new Blob([body], { type: 'application/json' })
        navigator.sendBeacon?.(`/rest/v1/user_sessions?id=eq.${sid}`, blob)
      }
    }

    window.addEventListener('beforeunload', handleBeforeUnload)

    return () => {
      clearInterval(interval)
      window.removeEventListener('beforeunload', handleBeforeUnload)
    }
  }, [user])

  const signIn = async (email: string, password: string) => {
    const { data, error } = await supabase.auth.signInWithPassword({ email, password })
    if (!error && data.user) {
      // A fresh login always starts a brand-new session row so it shows up in
      // Acessos, even if a previous session was left open.
      currentSessionIdRef.current = null
      sessionPromiseRef.current = null
      await startNewSession(data.user.id)
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
      data: { user: currentUser },
    } = await supabase.auth.getUser()
    const userId = currentUser?.id || user?.id

    if (userId) {
      const sid = currentSessionIdRef.current
      currentSessionIdRef.current = null
      sessionPromiseRef.current = null

      if (sid) {
        await closeSession(sid)
      }
      // Always make sure no open session lingers for this user.
      await closeAllOpenSessions(userId)

      await supabase.from('logs').insert({
        action: 'LOGOUT',
        entity: 'auth',
        user: userId,
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
