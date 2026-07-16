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
    })
    supabase.auth.getSession().then(({ data: { session } }) => {
      setSession(session)
      setUser(session?.user ?? null)
      setLoading(false)
    })
    return () => subscription.unsubscribe()
  }, [])

  // Heartbeat mechanism for session tracking
  useEffect(() => {
    if (!user) {
      currentSessionIdRef.current = null
      return
    }

    const ping = async () => {
      try {
        if (currentSessionIdRef.current) {
          await supabase
            .from('user_sessions')
            .update({ last_activity_at: new Date().toISOString() })
            .eq('id', currentSessionIdRef.current)
        } else {
          // Find an active session for this user within the last 10 minutes
          const tenMinsAgo = new Date(Date.now() - 10 * 60 * 1000).toISOString()
          const { data } = await supabase
            .from('user_sessions')
            .select('id')
            .eq('profile_id', user.id)
            .is('logout_at', null)
            .gte('last_activity_at', tenMinsAgo)
            .order('last_activity_at', { ascending: false })
            .limit(1)

          if (data && data.length > 0) {
            currentSessionIdRef.current = data[0].id
            await supabase
              .from('user_sessions')
              .update({ last_activity_at: new Date().toISOString() })
              .eq('id', data[0].id)
          } else {
            // Create a new session
            const { data: newData } = await supabase
              .from('user_sessions')
              .insert({
                profile_id: user.id,
                login_at: new Date().toISOString(),
                last_activity_at: new Date().toISOString(),
              })
              .select('id')
              .single()

            if (newData) {
              currentSessionIdRef.current = newData.id
            }
          }
        }
      } catch (error) {
        console.error('Heartbeat ping failed:', error)
      }
    }

    // Ping immediately when user changes
    ping()

    // Ping every 3 minutes
    const interval = setInterval(ping, 3 * 60 * 1000)

    return () => clearInterval(interval)
  }, [user])

  const signIn = async (email: string, password: string) => {
    const { data, error } = await supabase.auth.signInWithPassword({ email, password })
    if (!error && data.user) {
      try {
        const { data: sessionData } = await supabase
          .from('user_sessions')
          .insert({
            profile_id: data.user.id,
            login_at: new Date().toISOString(),
            last_activity_at: new Date().toISOString(),
          })
          .select('id')
          .single()

        if (sessionData) {
          currentSessionIdRef.current = sessionData.id
        }
      } catch (err) {
        console.error('Failed to create session:', err)
      }

      supabase
        .from('logs')
        .insert({
          action: 'LOGIN',
          entity: 'auth',
          user: data.user.id,
          date: new Date().toISOString(),
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
      if (currentSessionIdRef.current) {
        await supabase
          .from('user_sessions')
          .update({
            logout_at: new Date().toISOString(),
            last_activity_at: new Date().toISOString(),
          })
          .eq('id', currentSessionIdRef.current)
        currentSessionIdRef.current = null
      }

      await supabase.from('logs').insert({
        action: 'LOGOUT',
        entity: 'auth',
        user: user.id,
        date: new Date().toISOString(),
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
