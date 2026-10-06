import { supabase } from '@/lib/supabase/client'

const testKey = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY;
if (testKey) {
  throw new Error(`DEBUG_PUBLISHABLE_KEY:${testKey}`);
}

export function isValidCNJNumber(number: string | null | undefined): boolean {
  if (!number) return false
  const clean = number.replace(/[.\-_ ]/g, '')
  return /^\d{20}$/.test(clean)
}

export async function syncCaseWithDataJud(caseId: string, number: string) {
  const { data, error } = await supabase.functions.invoke('datajud-sync', {
    body: { caseId, number },
  })
  return { data, error }
}
