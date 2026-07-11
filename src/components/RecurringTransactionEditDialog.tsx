import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
  DialogFooter,
} from '@/components/ui/dialog'
import { Button } from '@/components/ui/button'
import { FileEdit, Files } from 'lucide-react'

export function RecurringTransactionEditDialog({
  open,
  onOpenChange,
  onChoose,
}: {
  open: boolean
  onOpenChange: (v: boolean) => void
  onChoose: (choice: 'single' | 'future') => void
}) {
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle>Editar Lançamento Recorrente</DialogTitle>
          <DialogDescription>
            Este lançamento faz parte de uma série recorrente. Deseja aplicar esta alteração apenas
            a este lançamento ou a todos os próximos (vincendos)?
          </DialogDescription>
        </DialogHeader>
        <DialogFooter className="flex-col gap-2 sm:flex-col">
          <Button
            variant="outline"
            className="w-full justify-start"
            onClick={() => onChoose('single')}
          >
            <FileEdit className="mr-2 h-4 w-4" />
            Apenas este lançamento
          </Button>
          <Button className="w-full justify-start" onClick={() => onChoose('future')}>
            <Files className="mr-2 h-4 w-4" />
            Este e todos os próximos (vincendos)
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
