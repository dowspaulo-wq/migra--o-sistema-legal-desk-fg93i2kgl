import { supabase } from '@/lib/supabase/client'

export interface DocumentTemplate {
  id: string
  name: string
  file_path: string
  category: string
  created_at: string
}

export async function fetchDocumentTemplates() {
  const { data, error } = await supabase
    .from('document_templates' as any)
    .select('*')
    .order('created_at', { ascending: false })
  return { data: (data as DocumentTemplate[]) || [], error }
}

export async function uploadDocumentTemplate(file: File, category: string) {
  const ext = file.name.split('.').pop()?.toLowerCase()
  if (ext !== 'docx') {
    return { error: { message: 'Formato não suportado. Utilize apenas arquivos .docx' } }
  }

  const fileName = `${Date.now()}_${file.name}`
  const { error: uploadError } = await supabase.storage
    .from('document_templates')
    .upload(fileName, file)

  if (uploadError) return { error: uploadError }

  const { data, error } = await supabase
    .from('document_templates' as any)
    .insert({
      name: file.name.replace(/\.docx$/i, ''),
      file_path: fileName,
      category,
    })
    .select()
    .single()

  return { data: data as DocumentTemplate, error }
}

export async function deleteDocumentTemplate(id: string, filePath: string) {
  await supabase.storage.from('document_templates').remove([filePath])
  const { error } = await supabase
    .from('document_templates' as any)
    .delete()
    .eq('id', id)
  return { error }
}
