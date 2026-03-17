import * as React from 'react'
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover'
import { Button } from '@/components/ui/button'
import { Checkbox } from '@/components/ui/checkbox'
import { ChevronDown } from 'lucide-react'
import { cn } from '@/lib/utils'

export function MultiSelect({
  options = [],
  values = [],
  onChange,
  placeholder,
  className,
}: {
  options: string[]
  values: string[]
  onChange: (v: string[]) => void
  placeholder: string
  className?: string
}) {
  return (
    <Popover>
      <PopoverTrigger asChild>
        <Button
          variant="outline"
          className={cn('w-full justify-between font-normal bg-background px-3', className)}
        >
          <span className="truncate">
            {values.length === 0 ? placeholder : `${values.length} selecionado(s)`}
          </span>
          <ChevronDown className="h-4 w-4 opacity-50 shrink-0" />
        </Button>
      </PopoverTrigger>
      <PopoverContent className="w-[--radix-popover-trigger-width] p-2" align="start">
        <div className="space-y-2 max-h-48 overflow-y-auto">
          {options.map((opt) => (
            <label
              key={opt}
              className="flex items-center gap-2 cursor-pointer hover:bg-muted/50 p-1 rounded"
            >
              <Checkbox
                checked={values.includes(opt)}
                onCheckedChange={(c) => {
                  if (c) onChange([...values, opt])
                  else onChange(values.filter((v) => v !== opt))
                }}
              />
              <span className="text-sm font-medium">{opt}</span>
            </label>
          ))}
        </div>
      </PopoverContent>
    </Popover>
  )
}
