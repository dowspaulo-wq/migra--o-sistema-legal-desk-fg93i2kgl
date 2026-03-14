import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Calendar } from '@/components/ui/calendar'
import { useState } from 'react'
import { ptBR } from 'date-fns/locale'

export default function Agenda() {
  const [date, setDate] = useState<Date | undefined>(new Date())

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-3xl font-bold tracking-tight text-slate-800 dark:text-slate-100">
          Agenda
        </h1>
        <p className="text-muted-foreground mt-1">Controle de prazos e audiências.</p>
      </div>

      <div className="grid gap-6 md:grid-cols-3">
        <Card className="shadow-sm md:col-span-1 h-fit">
          <CardContent className="p-4 flex justify-center">
            <Calendar mode="single" selected={date} onSelect={setDate} className="rounded-md" />
          </CardContent>
        </Card>

        <Card className="shadow-sm md:col-span-2">
          <CardHeader>
            <CardTitle>Compromissos para {date?.toLocaleDateString('pt-BR') || 'Hoje'}</CardTitle>
          </CardHeader>
          <CardContent>
            <div className="space-y-4">
              <div className="flex border-l-4 border-amber-500 pl-4 py-2 bg-slate-50">
                <div className="w-16 font-medium text-slate-600">10:00</div>
                <div>
                  <p className="font-bold text-slate-800">Audiência de Conciliação</p>
                  <p className="text-sm text-muted-foreground">
                    Processo 0005555-33 - Cliente: Empresa Alpha
                  </p>
                </div>
              </div>
              <div className="flex border-l-4 border-blue-500 pl-4 py-2 bg-slate-50">
                <div className="w-16 font-medium text-slate-600">14:30</div>
                <div>
                  <p className="font-bold text-slate-800">Reunião com Cliente</p>
                  <p className="text-sm text-muted-foreground">João Carlos Santos</p>
                </div>
              </div>
              <div className="flex border-l-4 border-emerald-500 pl-4 py-2 bg-slate-50">
                <div className="w-16 font-medium text-slate-600">16:00</div>
                <div>
                  <p className="font-bold text-slate-800">Prazo Petição</p>
                  <p className="text-sm text-muted-foreground">Processo 0004444-22</p>
                </div>
              </div>
            </div>
          </CardContent>
        </Card>
      </div>
    </div>
  )
}
