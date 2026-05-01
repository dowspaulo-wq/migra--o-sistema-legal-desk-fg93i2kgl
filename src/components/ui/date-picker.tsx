import * as React from 'react'
import { format } from 'date-fns'
import { Calendar as CalendarIcon } from 'lucide-react'

import { cn } from '@/lib/utils'
import { Button } from '@/components/ui/button'
import { Calendar } from '@/components/ui/calendar'
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover'
import { Input } from '@/components/ui/input'

export function DatePicker({
  value,
  onChange,
  placeholder = 'DD/MM/AAAA',
  className,
}: {
  value: string
  onChange: (v: string) => void
  placeholder?: string
  className?: string
}) {
  const [inputValue, setInputValue] = React.useState('')
  const [isOpen, setIsOpen] = React.useState(false)

  React.useEffect(() => {
    if (value) {
      const [y, m, d] = value.split('-')
      if (y && m && d) {
        setInputValue(`${d}/${m}/${y}`)
      } else {
        setInputValue(value)
      }
    } else {
      setInputValue('')
    }
  }, [value])

  const handleInputChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    let val = e.target.value.replace(/\D/g, '')
    if (val.length > 8) val = val.slice(0, 8)

    let formatted = val
    if (val.length > 4) {
      formatted = `${val.slice(0, 2)}/${val.slice(2, 4)}/${val.slice(4)}`
    } else if (val.length > 2) {
      formatted = `${val.slice(0, 2)}/${val.slice(2)}`
    }

    setInputValue(formatted)

    if (formatted.length === 10) {
      const parts = formatted.split('/')
      const d = parseInt(parts[0], 10)
      const m = parseInt(parts[1], 10)
      const y = parseInt(parts[2], 10)

      if (d > 0 && d <= 31 && m > 0 && m <= 12 && y > 1900) {
        const dateStr = `${y}-${parts[1].padStart(2, '0')}-${parts[0].padStart(2, '0')}`
        onChange(dateStr)
      }
    } else if (formatted.length === 0) {
      onChange('')
    }
  }

  const date = value ? new Date(value + 'T12:00:00') : undefined

  return (
    <Popover open={isOpen} onOpenChange={setIsOpen}>
      <div className="relative w-full">
        <Input
          type="text"
          placeholder={placeholder}
          value={inputValue}
          onChange={handleInputChange}
          className={cn('w-full pr-10', className)}
        />
        <PopoverTrigger asChild>
          <Button
            variant="ghost"
            size="icon"
            className="absolute right-0 top-0 h-full px-3 py-2 text-muted-foreground hover:bg-transparent"
          >
            <CalendarIcon className="h-4 w-4" />
          </Button>
        </PopoverTrigger>
      </div>
      <PopoverContent className="w-auto p-0" align="start">
        <Calendar
          mode="single"
          selected={date}
          onSelect={(d) => {
            if (d) {
              onChange(format(d, 'yyyy-MM-dd'))
              setIsOpen(false)
            } else {
              onChange('')
            }
          }}
          initialFocus
        />
      </PopoverContent>
    </Popover>
  )
}
