import { Bell, Search, AlertCircle, LogOut } from 'lucide-react'
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

export default function Header() {
  const { state } = useLegalStore()
  const { signOut } = useAuth()
  const pendingProtocol = state.tasks.filter((t) => t.status === 'Aguarda protocolo').length

  return (
    <header className="sticky top-0 z-30 flex h-16 w-full items-center justify-between border-b bg-white px-4 shadow-sm md:px-6">
      <div className="flex items-center gap-4 flex-1">
        <SidebarTrigger className="md:hidden text-slate-500 hover:text-primary" />
        <div className="relative w-full max-w-md hidden md:flex items-center">
          <Search className="absolute left-2.5 h-4 w-4 text-muted-foreground" />
          <Input
            type="search"
            placeholder="Busca global SBJur..."
            className="w-full bg-slate-50 pl-9 border-none focus-visible:ring-1"
          />
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
        <Button variant="ghost" size="icon" className="relative text-slate-500 hover:text-primary">
          <Bell className="h-5 w-5" />
        </Button>
        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <Button
              variant="ghost"
              className="relative h-8 w-8 rounded-full border-2"
              style={{ borderColor: state.currentUser.color }}
            >
              <Avatar className="h-8 w-8">
                <AvatarImage
                  src={`https://img.usecurling.com/ppl/thumbnail?gender=male&seed=${state.currentUser.id}`}
                  alt="User"
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
