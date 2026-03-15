import { useState } from 'react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Switch } from '@/components/ui/switch'
import { Label } from '@/components/ui/label'
import { MessageCircle, Send, Search, Bot } from 'lucide-react'
import useLegalStore from '@/stores/useLegalStore'

export default function WhatsApp() {
  const { state } = useLegalStore()
  const [activeContact, setActiveContact] = useState<string | null>(null)
  const [message, setMessage] = useState('')
  const [autoReply, setAutoReply] = useState(true)

  const contacts = Array.from(new Set(state.whatsappMessages.map((m) => m.phone))).map((phone) => {
    const msgs = state.whatsappMessages.filter((m) => m.phone === phone)
    return {
      phone,
      name: msgs[0].contact_name,
      lastMessage: msgs[msgs.length - 1],
    }
  })

  const activeMessages = state.whatsappMessages.filter((m) => m.phone === activeContact)

  return (
    <div className="space-y-6 h-full flex flex-col">
      <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4">
        <div>
          <h1 className="text-3xl font-bold tracking-tight flex items-center gap-2">
            <MessageCircle className="h-8 w-8 text-green-500" /> WhatsApp AI
          </h1>
          <p className="text-muted-foreground">Monitoramento de conversas e agente inteligente.</p>
        </div>
        <div className="flex items-center gap-3 bg-slate-50 p-2 px-4 border rounded-full">
          <Bot className="h-5 w-5 text-primary" />
          <div className="space-y-0.5">
            <Label className="text-sm font-bold">Agente AI (Respostas Automáticas)</Label>
          </div>
          <Switch checked={autoReply} onCheckedChange={setAutoReply} />
        </div>
      </div>

      <div className="flex flex-col md:flex-row gap-6 flex-1 h-[600px]">
        <Card className="w-full md:w-80 shrink-0 h-full flex flex-col overflow-hidden">
          <CardHeader className="py-3 border-b">
            <div className="relative">
              <Search className="absolute left-2.5 top-2.5 h-4 w-4 text-muted-foreground" />
              <Input type="search" placeholder="Buscar conversas..." className="pl-9 bg-slate-50" />
            </div>
          </CardHeader>
          <CardContent className="p-0 flex-1 overflow-y-auto">
            {contacts.map((c) => (
              <button
                key={c.phone}
                onClick={() => setActiveContact(c.phone)}
                className={`w-full text-left p-4 border-b hover:bg-slate-50 transition-colors ${activeContact === c.phone ? 'bg-slate-100 border-l-4 border-l-green-500' : ''}`}
              >
                <div className="font-semibold text-sm truncate">{c.name}</div>
                <div className="text-xs text-muted-foreground truncate mt-1">
                  {c.lastMessage.direction === 'outbound' && 'Você: '}
                  {c.lastMessage.message}
                </div>
              </button>
            ))}
            {contacts.length === 0 && (
              <div className="p-4 text-center text-sm text-muted-foreground">
                Nenhuma conversa encontrada.
              </div>
            )}
          </CardContent>
        </Card>

        <Card className="flex-1 h-full flex flex-col overflow-hidden bg-slate-50/50">
          {activeContact ? (
            <>
              <CardHeader className="py-3 border-b bg-white">
                <CardTitle className="text-base">
                  {contacts.find((c) => c.phone === activeContact)?.name}
                </CardTitle>
                <p className="text-xs text-muted-foreground">{activeContact}</p>
              </CardHeader>
              <CardContent className="p-4 flex-1 overflow-y-auto space-y-4">
                {activeMessages.map((m) => (
                  <div
                    key={m.id}
                    className={`flex ${m.direction === 'outbound' ? 'justify-end' : 'justify-start'}`}
                  >
                    <div
                      className={`max-w-[80%] rounded-lg p-3 text-sm shadow-sm ${m.direction === 'outbound' ? 'bg-green-100 text-green-900 rounded-tr-none' : 'bg-white border rounded-tl-none'}`}
                    >
                      {m.message}
                      <div className="text-[10px] text-right mt-1 opacity-60">
                        {new Date(m.created_at).toLocaleTimeString('pt-BR', {
                          hour: '2-digit',
                          minute: '2-digit',
                        })}
                      </div>
                    </div>
                  </div>
                ))}
              </CardContent>
              <div className="p-3 bg-white border-t flex gap-2">
                <Input
                  value={message}
                  onChange={(e) => setMessage(e.target.value)}
                  placeholder="Digite uma mensagem manual..."
                  className="flex-1"
                  onKeyDown={(e) => {
                    if (e.key === 'Enter' && message) {
                      setMessage('')
                    }
                  }}
                />
                <Button size="icon" onClick={() => setMessage('')} disabled={!message}>
                  <Send className="h-4 w-4" />
                </Button>
              </div>
            </>
          ) : (
            <div className="flex-1 flex items-center justify-center flex-col text-muted-foreground opacity-50">
              <MessageCircle className="h-16 w-16 mb-4" />
              <p>Selecione uma conversa para visualizar.</p>
            </div>
          )}
        </Card>
      </div>
    </div>
  )
}
