import { Link, useLocation } from 'react-router-dom'
import {
  Scale,
  LayoutDashboard,
  Users,
  Briefcase,
  Calendar as CalendarIcon,
  CheckSquare,
  Settings,
} from 'lucide-react'
import {
  Sidebar,
  SidebarContent,
  SidebarGroup,
  SidebarGroupContent,
  SidebarHeader,
  SidebarMenu,
  SidebarMenuButton,
  SidebarMenuItem,
  useSidebar,
} from '@/components/ui/sidebar'
import { cn } from '@/lib/utils'

const navigation = [
  { name: 'Painel', href: '/', icon: LayoutDashboard },
  { name: 'Clientes', href: '/clientes', icon: Users },
  { name: 'Processos', href: '/processos', icon: Briefcase },
  { name: 'Agenda', href: '/agenda', icon: CalendarIcon },
  { name: 'Tarefas', href: '/tarefas', icon: CheckSquare },
  { name: 'Configurações', href: '/configuracoes', icon: Settings },
]

export default function AppSidebar() {
  const location = useLocation()
  const { state } = useSidebar()

  return (
    <Sidebar collapsible="icon" className="border-r shadow-sm">
      <SidebarHeader className="p-4 flex items-center gap-3">
        <div className="flex h-8 w-8 items-center justify-center rounded-md bg-primary text-primary-foreground shrink-0 transition-transform">
          <Scale className="h-5 w-5" />
        </div>
        <span
          className={cn(
            'font-bold text-lg text-sidebar-foreground truncate transition-opacity duration-200',
            state === 'collapsed' ? 'opacity-0 hidden' : 'opacity-100',
          )}
        >
          Legal Desk
        </span>
      </SidebarHeader>
      <SidebarContent>
        <SidebarGroup>
          <SidebarGroupContent>
            <SidebarMenu>
              {navigation.map((item) => {
                const isActive =
                  location.pathname === item.href ||
                  (item.href !== '/' && location.pathname.startsWith(item.href))
                return (
                  <SidebarMenuItem key={item.name}>
                    <SidebarMenuButton
                      asChild
                      isActive={isActive}
                      tooltip={item.name}
                      className={cn(
                        'transition-all duration-200',
                        isActive && 'bg-sidebar-accent font-medium text-white',
                      )}
                    >
                      <Link to={item.href} className="flex items-center gap-3">
                        <item.icon className="h-5 w-5" />
                        <span>{item.name}</span>
                      </Link>
                    </SidebarMenuButton>
                  </SidebarMenuItem>
                )
              })}
            </SidebarMenu>
          </SidebarGroupContent>
        </SidebarGroup>
      </SidebarContent>
    </Sidebar>
  )
}
