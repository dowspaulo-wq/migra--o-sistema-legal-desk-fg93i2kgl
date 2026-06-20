import { useState, useEffect } from 'react'
import { Label } from '@/components/ui/label'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import { supabase } from '@/lib/supabase/client'

export function CaseSystemSelect({
  value,
  onChange,
}: {
  value: string
  onChange: (v: string) => void
}) {
  const [systems, setSystems] = useState<{ id: string; name: string }[]>([])

  useEffect(() => {
    supabase
      .from('case_systems')
      .select('id, name')
      .order('name')
      .then(({ data }) => {
        if (data) setSystems(data)
      })
  }, [])

  return (
    <div className="space-y-2 mt-4 w-full">
      <Label>Sistema</Label>
      <Select value={value} onValueChange={onChange}>
        <SelectTrigger className="w-full">
          <SelectValue placeholder="Selecione um sistema..." />
        </SelectTrigger>
        <SelectContent>
          {systems.map((s) => (
            <SelectItem key={s.id} value={s.name}>
              {s.name}
            </SelectItem>
          ))}
        </SelectContent>
      </Select>
    </div>
  )
}
