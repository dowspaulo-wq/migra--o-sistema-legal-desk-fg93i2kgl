import { Bell, Search, AlertCircle, LogOut, Upload } from 'lucide-react'
import { Input } from '@/components/ui/input'
import { Avatar, AvatarFallback, AvatarImage } from '@/components/ui/avatar'
import { Button } from '@/components/ui/button'
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu'
import { SidebarTrigger } from '@/components/ui/sidebar'
import useLegalStore from '@/stores/useLegalStore'
import { useAuth } from '@/hooks/use-auth'
import { Link } from 'react-router-dom'
import { toast } from '@/hooks/use-toast'
import { supabase } from '@/lib/supabase/client'
import { useState, useMemo } from 'react'

const verses = [
  'O Senhor é o meu pastor; nada me faltará. - Salmos 23:1',
  'Tudo posso naquele que me fortalece. - Filipenses 4:13',
  'Ainda que eu ande pelo vale da sombra da morte, não temerei mal nenhum... - Salmos 23:4',
  'Deixo-vos a paz, a minha paz vos dou... - João 14:27',
  'Entregue o seu caminho ao Senhor; confie nele, e ele agirá. - Salmos 37:5',
  'Porque sou eu que conheço os planos que tenho para vocês... - Jeremias 29:11',
  'O Senhor é a minha luz e a minha salvação; de quem terei temor? - Salmos 27:1',
]

export default function Header() {
  const { state, updateUser } = useLegalStore()
  const { signOut } = useAuth()
  const [isUploading, setIsUploading] = useState(false)
  const pendingProtocol = state.tasks.filter((t) => t.status === 'Aguarda protocolo').length

  const dailyVerse = useMemo(() => {
    const dayOfYear = Math.floor(
      (Date.now() - new Date(new Date().getFullYear(), 0, 0).getTime()) / 86400000,
    )
    return verses[dayOfYear % verses.length]
  }, [])

  const uploadAvatar = async (event: React.ChangeEvent<HTMLInputElement>) => {
    const file = event.target.files?.[0]
    if (!file) return
    setIsUploading(true)

    try {
      const fileExt = file.name.split('.').pop()
      const fileName = `${state.currentUser.id}-${Math.random()}.${fileExt}`

      const { error: uploadError } = await supabase.storage.from('avatars').upload(fileName, file)
      if (uploadError) throw uploadError

      const { data } = supabase.storage.from('avatars').getPublicUrl(fileName)
      await updateUser(state.currentUser.id, { avatar_url: data.publicUrl })
      toast({ title: 'Sucesso', description: 'Foto de perfil atualizada!' })
    } catch (err: any) {
      toast({
        title: 'Erro',
        description: err.message || 'Erro ao fazer upload da imagem',
        variant: 'destructive',
      })
    } finally {
      setIsUploading(false)
    }
  }

  return (
    <header className="sticky top-0 z-30 flex h-16 w-full items-center justify-between border-b bg-white px-4 shadow-sm md:px-6">
      <div className="flex items-center gap-4 flex-1">
        <SidebarTrigger className="md:hidden text-slate-500 hover:text-primary" />
        <div className="hidden md:block flex-1">
          <p className="text-sm font-semibold text-slate-800">
            Bem vindo, {state.currentUser.name.split(' ')[0]}
          </p>
          <p className="text-xs text-muted-foreground italic max-w-lg truncate">{dailyVerse}</p>
        </div>
      </div>
      <div className="flex items-center gap-4">
        {pendingProtocol > 0 && (
          <Link
            to="/tarefas?status=Aguarda+protocolo"
            className="hidden md:flex items-center text-xs font-semibold text-destructive bg-destructive/10 px-3 py-1.5 rounded-full animate-pulse hover:bg-destructive/20 transition-colors"
          >
            <AlertCircle className="h-4 w-4 mr-1" /> {pendingProtocol} Protocolos Pendentes
          </Link>
        )}

        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <Button
              variant="ghost"
              className="relative h-9 w-9 rounded-full border-2 p-0 overflow-hidden"
              style={{ borderColor: state.currentUser.color }}
            >
              <Avatar className="h-full w-full">
                <AvatarImage
                  src={
                    state.currentUser.avatar_url ||
                    `https://img.usecurling.com/ppl/thumbnail?gender=male&seed=${state.currentUser.id}`
                  }
                  alt="User"
                  className="object-cover"
                />
                <AvatarFallback>
                  {state.currentUser.name.substring(0, 2).toUpperCase()}
                </AvatarFallback>
              </Avatar>
            </Button>
          </DropdownMenuTrigger>
          <DropdownMenuContent className="w-56" align="end" forceMount>
            <DropdownMenuLabel className="font-normal">
              <div className="flex flex-col space-y-1">
                <p className="text-sm font-medium leading-none">{state.currentUser.name}</p>
                <p className="text-xs leading-none text-muted-foreground">
                  {state.currentUser.role}
                </p>
              </div>
            </DropdownMenuLabel>
            <DropdownMenuSeparator />
            <DropdownMenuItem asChild>
              <label className="cursor-pointer flex items-center w-full">
                <Upload className="mr-2 h-4 w-4" />
                {isUploading ? 'Enviando...' : 'Alterar Foto'}
                <input
                  type="file"
                  className="hidden"
                  accept="image/*"
                  onChange={uploadAvatar}
                  disabled={isUploading}
                />
              </label>
            </DropdownMenuItem>
            <DropdownMenuItem asChild>
              <Link to="/configuracoes">Perfil & Ajustes</Link>
            </DropdownMenuItem>
            <DropdownMenuSeparator />
            <DropdownMenuItem className="text-destructive cursor-pointer" onClick={signOut}>
              <LogOut className="mr-2 h-4 w-4" /> Sair
            </DropdownMenuItem>
          </DropdownMenuContent>
        </DropdownMenu>
      </div>
    </header>
  )
}
