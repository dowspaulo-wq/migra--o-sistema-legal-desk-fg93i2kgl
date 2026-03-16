import { useState } from 'react'
import { ChevronLeft, ChevronRight } from 'lucide-react'
import { Button } from '@/components/ui/button'

export function FullCalendar<T extends { id: string; date: string }>({
  items,
  renderItem,
  onDayClick,
}: {
  items: T[]
  renderItem: (item: T) => React.ReactNode
  onDayClick?: (date: Date) => void
}) {
  const [date, setDate] = useState(new Date())
  const year = date.getFullYear()
  const month = date.getMonth()
  const daysInMonth = new Date(year, month + 1, 0).getDate()
  const firstDay = new Date(year, month, 1).getDay()

  const days = Array.from({ length: 42 }, (_, i) => {
    const d = i - firstDay + 1
    if (d > 0 && d <= daysInMonth) return new Date(year, month, d)
    return null
  })

  return (
    <div className="flex flex-col gap-4">
      <div className="flex justify-between items-center bg-card p-2 rounded-lg border shadow-sm">
        <Button variant="ghost" onClick={() => setDate(new Date(year, month - 1, 1))}>
          <ChevronLeft className="h-4 w-4" />
        </Button>
        <span className="font-bold text-lg capitalize">
          {date.toLocaleString('pt-BR', { month: 'long', year: 'numeric' })}
        </span>
        <div className="flex gap-2">
          <Button variant="outline" size="sm" onClick={() => setDate(new Date())}>
            Hoje
          </Button>
          <Button variant="ghost" onClick={() => setDate(new Date(year, month + 1, 1))}>
            <ChevronRight className="h-4 w-4" />
          </Button>
        </div>
      </div>
      <div className="grid grid-cols-7 gap-2">
        {['Dom', 'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb'].map((d) => (
          <div key={d} className="text-center font-semibold text-sm text-muted-foreground py-2">
            {d}
          </div>
        ))}
        {days.map((d, i) => (
          <div
            key={i}
            className={`min-h-[140px] border rounded-lg p-1 bg-card ${d ? 'hover:border-primary/50 cursor-pointer' : 'bg-muted/30'}`}
            onClick={() => d && onDayClick?.(d)}
          >
            {d && (
              <>
                <div
                  className={`text-right text-xs p-1 mb-1 ${d.toDateString() === new Date().toDateString() ? 'font-bold text-primary bg-primary/10 rounded w-fit ml-auto' : 'text-muted-foreground'}`}
                >
                  {d.getDate()}
                </div>
                <div className="flex flex-col gap-1 overflow-y-auto max-h-[100px] scrollbar-hide">
                  {items
                    .filter((item) => new Date(item.date).toDateString() === d.toDateString())
                    .map(renderItem)}
                </div>
              </>
            )}
          </div>
        ))}
      </div>
    </div>
  )
}
