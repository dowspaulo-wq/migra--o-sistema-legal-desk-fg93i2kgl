import { useState, useEffect } from 'react'
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Trash2, Plus, Upload, Image as ImageIcon } from 'lucide-react'
import { useToast } from '@/hooks/use-toast'
import { supabase } from '@/lib/supabase/client'

export function SystemManagement() {
  const [systems, setSystems] = useState<{ id: string; name: string; image_url: string | null }[]>(
    [],
  )
  const [newSystem, setNewSystem] = useState('')
  const [loading, setLoading] = useState(false)
  const [uploadingId, setUploadingId] = useState<string | null>(null)
  const { toast } = useToast()

  const fetchSystems = async () => {
    const { data } = await supabase.from('case_systems').select('*').order('name')
    if (data) setSystems(data)
  }

  useEffect(() => {
    fetchSystems()
  }, [])

  const handleAdd = async () => {
    if (!newSystem.trim()) return
    setLoading(true)
    const { error } = await supabase.from('case_systems').insert({ name: newSystem.trim() })
    setLoading(false)
    if (error) {
      toast({ title: 'Erro', description: error.message, variant: 'destructive' })
    } else {
      setNewSystem('')
      fetchSystems()
      toast({ title: 'Sucesso', description: 'Sistema adicionado.' })
    }
  }

  const handleDelete = async (id: string) => {
    const { error } = await supabase.from('case_systems').delete().eq('id', id)
    if (error) {
      toast({ title: 'Erro', description: error.message, variant: 'destructive' })
    } else {
      fetchSystems()
      toast({ title: 'Sucesso', description: 'Sistema removido.' })
    }
  }

  const handleImageUpload = async (id: string, file: File) => {
    setUploadingId(id)
    const fileExt = file.name.split('.').pop()
    const fileName = `${Math.random()}.${fileExt}`
    const filePath = `${fileName}`

    const { error: uploadError } = await supabase.storage
      .from('case-systems')
      .upload(filePath, file, { upsert: true })

    if (uploadError) {
      toast({ title: 'Erro', description: uploadError.message, variant: 'destructive' })
      setUploadingId(null)
      return
    }

    const {
      data: { publicUrl },
    } = supabase.storage.from('case-systems').getPublicUrl(filePath)

    const { error: updateError } = await supabase
      .from('case_systems')
      .update({ image_url: publicUrl })
      .eq('id', id)

    setUploadingId(null)
    if (updateError) {
      toast({ title: 'Erro', description: updateError.message, variant: 'destructive' })
    } else {
      fetchSystems()
      toast({ title: 'Sucesso', description: 'Ícone atualizado.' })
    }
  }

  return (
    <Card className="shadow-sm mt-6">
      <CardHeader>
        <CardTitle>Sistemas Legais</CardTitle>
        <CardDescription>
          Gerencie os sistemas judiciais (ex: E-PROC, PJE) e seus ícones associados.
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-4">
        <div className="flex gap-2">
          <Input
            value={newSystem}
            onChange={(e) => setNewSystem(e.target.value)}
            placeholder="Nome do sistema..."
            onKeyDown={(e) => e.key === 'Enter' && handleAdd()}
            disabled={loading}
          />
          <Button onClick={handleAdd} disabled={loading || !newSystem.trim()}>
            <Plus className="h-4 w-4 mr-2" /> Adicionar
          </Button>
        </div>

        <div className="border rounded-md divide-y">
          {systems.map((sys) => (
            <div
              key={sys.id}
              className="flex items-center justify-between p-3 bg-card hover:bg-accent/50 transition-colors"
            >
              <div className="flex items-center gap-3">
                <div className="relative group w-10 h-10 border rounded bg-background flex items-center justify-center overflow-hidden shrink-0">
                  {sys.image_url ? (
                    <img
                      src={sys.image_url}
                      alt={sys.name}
                      className="w-full h-full object-contain p-1"
                    />
                  ) : (
                    <ImageIcon className="h-5 w-5 text-muted-foreground" />
                  )}
                  <label className="absolute inset-0 bg-black/50 text-white opacity-0 group-hover:opacity-100 flex items-center justify-center cursor-pointer transition-opacity">
                    {uploadingId === sys.id ? (
                      <span className="animate-spin w-4 h-4 border-2 border-white border-t-transparent rounded-full" />
                    ) : (
                      <Upload className="h-4 w-4" />
                    )}
                    <input
                      type="file"
                      accept="image/*"
                      className="hidden"
                      disabled={uploadingId === sys.id}
                      onChange={(e) => {
                        const file = e.target.files?.[0]
                        if (file) handleImageUpload(sys.id, file)
                      }}
                    />
                  </label>
                </div>
                <span className="font-medium">{sys.name}</span>
              </div>
              <Button variant="ghost" size="icon" onClick={() => handleDelete(sys.id)}>
                <Trash2 className="h-4 w-4 text-destructive" />
              </Button>
            </div>
          ))}
          {systems.length === 0 && (
            <div className="p-4 text-center text-muted-foreground text-sm">
              Nenhum sistema cadastrado.
            </div>
          )}
        </div>
      </CardContent>
    </Card>
  )
}
