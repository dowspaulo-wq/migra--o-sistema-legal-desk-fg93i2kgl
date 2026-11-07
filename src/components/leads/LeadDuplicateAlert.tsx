import { Alert, AlertDescription, AlertTitle } from '@/components/ui/alert'
import { AlertTriangle } from 'lucide-react'

export function UserWarning({ names }: { names: string }) {
  return (
    <Alert variant="destructive" className="border-amber-300 bg-amber-50 text-amber-900">
      <AlertTriangle className="h-4 w-4" />
      <AlertTitle className="text-sm">Provável lead duplicado</AlertTitle>
      <AlertDescription className="text-xs">
        Já existe(m) lead(s) com este telefone ou e-mail: <strong>{names}</strong>. Confira antes de
        salvar — o sistema não bloqueia o cadastro, mas evite duplicidades.
      </AlertDescription>
    </Alert>
  )
}
