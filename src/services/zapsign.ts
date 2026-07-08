import { supabase } from '@/lib/supabase/client'

export async function createZapSignDoc(caseId: string, clientId: string, docType: string) {
  const { data, error } = await supabase.functions.invoke('zapsign-integration', {
    body: { action: 'createDoc', caseId, clientId, docType },
  })
  return { data, error }
}
