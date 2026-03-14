import { useParams, Link } from 'react-router-dom'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { ArrowLeft, User, MapPin, Mail, MessageCircle, FileText } from 'lucide-react'
import useLegalStore from '@/stores/useLegalStore'

export default function ClientDetail() {
  const { id } = useParams<{ id: string }>()
  const { state } = useLegalStore()

  const client = state.clients.find((c) => c.id === id)
  const cases = state.cases.filter((c) => c.clientId === id)

  if (!client) return <div className="p-8 text-center">Cliente não encontrado.</div>

  return (
    <div className="space-y-6">
      <div className="flex items-center gap-4">
        <Button variant="outline" size="icon" asChild>
          <Link to="/clientes">
            <ArrowLeft className="h-4 w-4" />
          </Link>
        </Button>
        <div>
          <h1 className="text-3xl font-bold tracking-tight flex items-center gap-2 text-slate-800 dark:text-slate-100">
            {client.name} {client.isSpecial && <span className="text-yellow-400">★</span>}
          </h1>
          <p className="text-muted-foreground flex items-center gap-2 mt-1">
            <Badge variant={client.status === 'Ativo' ? 'default' : 'secondary'}>
              {client.status}
            </Badge>
            {client.type} - {client.document}
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
              <p className="font-medium text-sm">{client.email || 'Não informado'}</p>
            </div>
            <div>
              <p className="text-sm text-muted-foreground flex items-center gap-2">
                <MessageCircle className="h-4 w-4" /> Telefone
              </p>
              <p className="font-medium flex items-center gap-2 text-sm">
                {client.phone || 'Não informado'}
                {client.phone && (
                  <a
                    href={`https://wa.me/${client.phone.replace(/\D/g, '')}`}
                    target="_blank"
                    className="text-green-500"
                  >
                    <MessageCircle className="h-4 w-4" />
                  </a>
                )}
              </p>
            </div>
            <div>
              <p className="text-sm text-muted-foreground flex items-center gap-2">
                <MapPin className="h-4 w-4" /> Endereço
              </p>
              <p className="font-medium text-sm">{client.address || 'Não informado'}</p>
            </div>
          </CardContent>
        </Card>

        <Card className="md:col-span-2 shadow-sm">
          <CardHeader>
            <CardTitle className="text-lg flex items-center gap-2">
              <FileText className="h-5 w-5" /> Processos Vinculados ({cases.length})
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="space-y-4">
              {cases.map((c) => (
                <div
                  key={c.id}
                  className="flex justify-between items-center border p-3 rounded-lg hover:bg-slate-50"
                >
                  <div>
                    <Link
                      to={`/processos/${c.id}`}
                      className="font-bold text-primary hover:underline"
                    >
                      {c.number}
                    </Link>
                    <p className="text-sm text-muted-foreground">
                      {c.type} • {c.court} • {c.comarca}/{c.state}
                    </p>
                  </div>
                  <Badge variant="outline">{c.status}</Badge>
                </div>
              ))}
              {cases.length === 0 && (
                <p className="text-muted-foreground text-sm">Nenhum processo vinculado.</p>
              )}
            </div>
          </CardContent>
        </Card>
      </div>
    </div>
  )
}
