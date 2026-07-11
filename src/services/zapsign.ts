import { supabase } from '@/lib/supabase/client'

export async function createZapSignDoc(caseId: string, clientId: string, docType: string) {
  const { data, error } = await supabase.functions.invoke('zapsign-integration', {
    body: { action: 'createDoc', caseId, clientId, docType },
  })
  if (!error && data?.error) return { data: null, error: { message: data.error } }
  return { data, error }
}

export async function createDocFromTemplate(caseId: string, templateId: string) {
  const { data, error } = await supabase.functions.invoke('zapsign-integration', {
    body: { action: 'createDocFromTemplate', caseId, templateId },
  })
  if (!error && data?.error) return { data: null, error: { message: data.error } }
  return { data, error }
}
