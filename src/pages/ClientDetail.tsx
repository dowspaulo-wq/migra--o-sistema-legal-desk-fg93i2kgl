import { useParams, Link } from 'react-router-dom'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { ArrowLeft, User, Phone, Mail, FileText } from 'lucide-react'
import useLegalStore from '@/stores/useLegalStore'

export default function ClientDetail() {
  const { id } = useParams<{ id: string }>()
  const { state } = useLegalStore()

  const client = state.clients.find((c) => c.id === id)
  const clientCases = state.cases.filter((c) => c.clientId === id)

  if (!client) {
    return <div className="p-8 text-center">Cliente não encontrado.</div>
  }

  return (
    <div className="space-y-6">
      <div className="flex items-center gap-4">
        <Button variant="outline" size="icon" asChild>
          <Link to="/clientes">
            <ArrowLeft className="h-4 w-4" />
          </Link>
        </Button>
        <div>
          <h1 className="text-3xl font-bold tracking-tight text-slate-800 dark:text-slate-100">
            {client.name}
          </h1>
          <p className="text-muted-foreground flex items-center gap-2 mt-1">
            <Badge
              variant={client.status === 'Ativo' ? 'default' : 'secondary'}
              className={client.status === 'Ativo' ? 'bg-emerald-500' : ''}
            >
              {client.status}
            </Badge>
            {client.document}
          </p>
        </div>
      </div>

      <div className="grid gap-6 md:grid-cols-3">
        <Card className="md:col-span-1 shadow-sm">
          <CardHeader>
            <CardTitle className="text-lg flex items-center gap-2">
              <User className="h-5 w-5" /> Informações
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-4">
            <div>
              <p className="text-sm text-muted-foreground flex items-center gap-2">
                <Mail className="h-4 w-4" /> Email
              </p>
              <p className="font-medium">{client.email || 'Não informado'}</p>
            </div>
            <div>
              <p className="text-sm text-muted-foreground flex items-center gap-2">
                <Phone className="h-4 w-4" /> Telefone
              </p>
              <p className="font-medium">{client.phone || 'Não informado'}</p>
            </div>
          </CardContent>
        </Card>

        <Card className="md:col-span-2 shadow-sm">
          <CardHeader>
            <CardTitle className="text-lg flex items-center gap-2">
              <FileText className="h-5 w-5" /> Histórico de Processos
            </CardTitle>
          </CardHeader>
          <CardContent>
            {clientCases.length > 0 ? (
              <div className="space-y-4">
                {clientCases.map((c) => (
                  <div
                    key={c.id}
                    className="flex justify-between items-center border-b pb-4 last:border-0 last:pb-0"
                  >
                    <div>
                      <p className="font-medium text-primary hover:underline cursor-pointer">
                        {c.number}
                      </p>
                      <p className="text-sm text-muted-foreground">{c.title}</p>
                    </div>
                    <Badge variant="outline">{c.status}</Badge>
                  </div>
                ))}
              </div>
            ) : (
              <p className="text-muted-foreground text-center py-8">
                Nenhum processo vinculado a este cliente.
              </p>
            )}
          </CardContent>
        </Card>
      </div>
    </div>
  )
}
