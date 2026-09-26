import { createContext, useContext, useEffect, useState, useRef, ReactNode } from 'react'
import { User, Session } from '@supabase/supabase-js'
import { supabase } from '@/lib/supabase/client'

interface AuthContextType {
  user: User | null
  session: Session | null
  signIn: (email: string, password: string) => Promise<{ error: any }>
  signOut: () => Promise<{ error: any }>
  resetPassword: (email: string) => Promise<{ error: any }>
  updatePassword: (newPassword: string) => Promise<{ data?: any; error: any }>
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

/**
 * Executes a promise with a timeout limit so hanging Supabase network calls
 * never freeze the application or authentication flow indefinitely.
 */
function withTimeout<T>(promise: Promise<T>, ms: number, fallbackValue?: T): Promise<T> {
  let timer: any
  const timeoutPromise = new Promise<T>((resolve, reject) => {
    timer = setTimeout(() => {
      if (fallbackValue !== undefined) {
        resolve(fallbackValue)
      } else {
        reject(new Error(`Operação excedeu o tempo limite de ${ms}ms`))
      }
    }, ms)
  })

  return Promise.race([
    promise
      .then((res) => {
        clearTimeout(timer)
        return res
      })
      .catch((err) => {
        clearTimeout(timer)
        throw err
      }),
    timeoutPromise,
  ])
}

async function createSession(profileId: string): Promise<string | null> {
  try {
    const res = await withTimeout(
      Promise.resolve(
        supabase
          .from('user_sessions')
          .insert({
            profile_id: profileId,
            login_at: nowISO(),
            last_activity_at: nowISO(),
            date: getLocalDateString(),
          })
          .select('id')
          .single(),
      ),
      5000,
      { data: null, error: null } as any,
    )
    if (res.error) console.error('Failed to create session:', res.error)
    return res.data?.id ?? null
  } catch (err) {
    console.error('Failed to create session (timed out/failed):', err)
    return null
  }
}

async function findOpenSession(profileId: string): Promise<string | null> {
  try {
    const res = await withTimeout(
      Promise.resolve(
        supabase
          .from('user_sessions')
          .select('id')
          .eq('profile_id', profileId)
          .is('logout_at', null)
          .order('login_at', { ascending: false })
          .limit(1),
      ),
      4000,
      { data: null } as any,
    )
    return res.data?.[0]?.id ?? null
  } catch {
    return null
  }
}

async function closeSession(sessionId: string) {
  try {
    await withTimeout(
      Promise.resolve(
        supabase
          .from('user_sessions')
          .update({ logout_at: nowISO(), last_activity_at: nowISO() })
          .eq('id', sessionId)
          .is('logout_at', null),
      ),
      3000,
      null,
    )
  } catch (err) {
    console.error('Error closing session:', err)
  }
}

async function closeAllOpenSessions(profileId: string): Promise<void> {
  try {
    const { data } = await withTimeout(
      Promise.resolve(
        supabase
          .from('user_sessions')
          .select('id, last_activity_at, login_at')
          .eq('profile_id', profileId)
          .is('logout_at', null),
      ),
      4000,
      { data: null } as any,
    )
    if (data && data.length > 0) {
      const now = nowISO()
      const updatePromises = data.map((session: any) => {
        const computedLogout = session.last_activity_at || session.login_at || now
        return supabase
          .from('user_sessions')
          .update({ logout_at: computedLogout })
          .eq('id', session.id)
          .is('logout_at', null)
      })
      await withTimeout(Promise.all(updatePromises), 4000, [])
    }
  } catch (err) {
    console.error('Error in closeAllOpenSessions:', err)
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
    // Clean up any stale open sessions (> 2 hours without activity or from another day)
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
          s.date !== todayStr || (lastActiveMs > 0 && nowMs - lastActiveMs > 2 * 60 * 60 * 1000)

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

    // If we have an active in-memory sessionId, just update its heartbeat
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
    }

    // Check if there is an existing open session for today to adopt as currentSessionIdRef
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

    // Do NOT automatically create a new row in user_sessions on heartbeat/restored session!
    // Rows in user_sessions should ONLY be created upon explicit sign-in (signIn).
    return null
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

    // If the user is currently on /update-password (e.g. recovery flow),
    // skip heartbeat/active session check to avoid interference with the recovery session.
    if (window.location.pathname.startsWith('/update-password')) {
      return
    }

    const ping = async () => {
      try {
        if (window.location.pathname.startsWith('/update-password')) {
          return
        }

        const profileCheck = await withTimeout(
          Promise.resolve(
            supabase.from('profiles').select('is_active').eq('id', user.id).maybeSingle(),
          ),
          5000,
          { data: null, error: null } as any,
        )

        if (profileCheck.data && profileCheck.data.is_active === false) {
          await supabase.auth.signOut()
          window.location.href = '/login?inactive=1'
          return
        }

        await ensureActiveSession(user.id)
      } catch (error) {
        console.error('Heartbeat ping failed (non-fatal):', error)
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
    try {
      // 1. Authenticate with Supabase Auth with a 10s safety timeout
      const authResult = await withTimeout(
        supabase.auth.signInWithPassword({ email, password }),
        10000,
      )

      const { data, error } = authResult
      if (error) {
        return { error }
      }

      if (data?.user) {
        // 2. Check if user profile is inactive (using maybeSingle and 6s timeout)
        let profile: { is_active?: boolean | null } | null = null
        try {
          const profileRes = await withTimeout(
            Promise.resolve(
              supabase.from('profiles').select('is_active').eq('id', data.user.id).maybeSingle(),
            ),
            6000,
            { data: null, error: null } as any,
          )
          profile = profileRes.data
        } catch (profileErr) {
          console.warn('Could not check profile is_active in time:', profileErr)
        }

        if (profile && profile.is_active === false) {
          try {
            await supabase.auth.signOut()
          } catch (signOutErr) {
            console.error('Error signing out inactive user:', signOutErr)
          }
          return {
            error: {
              code: 'USER_INACTIVE',
              message: 'Usuário inativo. Contate o administrador.',
            },
          }
        }

        // 3. A fresh login always closes any previous open session and creates a brand-new one.
        // Handled in a non-blocking or timed background operation so session logging never blocks login.
        currentSessionIdRef.current = null
        sessionPromiseRef.current = null

        // Non-blocking session creation
        startNewSession(data.user.id).catch((sessionErr) => {
          console.error('Non-blocking error creating session record:', sessionErr)
        })

        // Non-blocking log
        try {
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
        } catch (logErr) {
          console.error('Non-blocking error logging signin:', logErr)
        }
      }

      return { error: null }
    } catch (err: any) {
      console.error('Unexpected signIn error:', err)
      return {
        error: {
          message:
            err?.message || 'Não foi possível autenticar. Verifique sua conexão e tente novamente.',
        },
      }
    }
  }

  const signOut = async () => {
    try {
      const {
        data: { user: currentUser },
      } = await supabase.auth.getUser().catch(() => ({ data: { user: null } }))
      const userId = currentUser?.id || user?.id

      if (userId) {
        const sid = currentSessionIdRef.current
        currentSessionIdRef.current = null
        sessionPromiseRef.current = null

        if (sid) {
          await closeSession(sid).catch(() => {})
        }
        // Always make sure no open session lingers for this user.
        await closeAllOpenSessions(userId).catch(() => {})

        try {
          await supabase.from('logs').insert({
            action: 'LOGOUT',
            entity: 'auth',
            user: userId,
            date: nowISO(),
            details: 'Logout realizado',
          })
        } catch {
          /* intentionally ignored */
        }
      }
    } catch (err) {
      console.warn('Non-blocking error during session cleanup on logout:', err)
    }

    // Clear local storage auth tokens to prevent stale / crossed sessions
    try {
      localStorage.removeItem(
        'sb-' +
          (import.meta.env.VITE_SUPABASE_URL || '').split('//')[1]?.split('.')[0] +
          '-auth-token',
      )
    } catch {
      /* intentionally ignored */
    }

    const { error } = await supabase.auth.signOut()
    setUser(null)
    setSession(null)
    return { error }
  }

  const resetPassword = async (email: string) => {
    try {
      const origin =
        typeof window !== 'undefined' && window.location?.origin
          ? window.location.origin
          : 'https://dpsadvocacia.goskip.app'
      const cleanEmail = email.trim()

      const result = await withTimeout(
        supabase.auth.resetPasswordForEmail(cleanEmail, {
          redirectTo: `${origin}/update-password`,
        }),
        10000,
      )
      return { error: result.error ?? null }
    } catch (err: any) {
      console.error('resetPassword error caught in use-auth:', err)
      return {
        error: {
          name: err?.name || 'AuthError',
          message:
            err?.message ||
            'Não foi possível conectar ao servidor para recuperar a senha. Tente novamente.',
          status: err?.status,
          code: err?.code,
        },
      }
    }
  }

  const updatePassword = async (newPassword: string) => {
    const { data, error } = await supabase.auth.updateUser({ password: newPassword })
    return { data, error }
  }

  return (
    <AuthContext.Provider
      value={{ user, session, signIn, signOut, resetPassword, updatePassword, loading }}
    >
      {children}
    </AuthContext.Provider>
  )
}
