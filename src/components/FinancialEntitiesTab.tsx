import { useState } from 'react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table'
import { Check, Edit2, Plus, Trash2, X } from 'lucide-react'
import { SupplierDialog } from '@/components/SupplierDialog'
import { Input } from '@/components/ui/input'
import useLegalStore from '@/stores/useLegalStore'
import { toast } from '@/hooks/use-toast'

export function FinancialEntitiesTab() {
  const { state, updateItem, addSupplier, renameType } = useLegalStore() as any
  const [editingSupplier, setEditingSupplier] = useState<any>(null)
  const [creatingSupplier, setCreatingSupplier] = useState(false)
  const [newCategory, setNewCategory] = useState('')
  const [editingCategory, setEditingCategory] = useState<string | null>(null)
  const [editValue, setEditValue] = useState('')

  const categories: string[] = (state.settings?.transactionCategories as string[]) || []

  const handleAddCategory = () => {
    if (!newCategory || categories.includes(newCategory)) return
    updateItem('settings', state.settings.id, {
      transactionCategories: [...categories, newCategory].sort(),
    })
    setNewCategory('')
  }

  const handleRemoveCategory = (cat: string) => {
    updateItem('settings', state.settings.id, {
      transactionCategories: categories.filter((c) => c !== cat),
    })
  }

  const startEditCategory = (cat: string) => {
    setEditingCategory(cat)
    setEditValue(cat)
  }

  const cancelEditCategory = () => {
    setEditingCategory(null)
    setEditValue('')
  }

  const saveEditCategory = () => {
    if (!editingCategory) return
    const trimmed = editValue.trim()
    if (!trimmed) {
      toast({ title: 'Erro', description: 'Nome inválido.', variant: 'destructive' })
      return
    }
    if (trimmed === editingCategory) {
      cancelEditCategory()
      return
    }
    if (categories.includes(trimmed)) {
      toast({
        title: 'Erro',
        description: 'Já existe uma categoria com esse nome.',
        variant: 'destructive',
      })
      return
    }
    // Update settings list (rename in place, keep sorted)
    updateItem('settings', state.settings.id, {
      transactionCategories: categories
        .map((c) => (c === editingCategory ? trimmed : c))
        .sort((a, b) => a.localeCompare(b)),
    })
    // Propagate rename to existing transactions
    renameType('transactions', 'category', editingCategory, trimmed)
    toast({ title: 'Sucesso', description: 'Categoria atualizada.' })
    cancelEditCategory()
  }

  const handleDeactivateSupplier = (supplier: any) => {
    updateItem('suppliers', supplier.id, { status: 'Inativo' })
  }

  return (
    <div className="space-y-6">
      <Card>
        <CardHeader className="flex flex-row items-center justify-between pb-2">
          <div>
            <CardTitle>Fornecedores</CardTitle>
            <p className="text-sm text-muted-foreground">
              Gerencie fornecedores do módulo financeiro.
            </p>
          </div>
          <Button size="sm" onClick={() => setCreatingSupplier(true)}>
            <Plus className="mr-2 h-4 w-4" /> Novo Fornecedor
          </Button>
        </CardHeader>
        <CardContent>
          <div className="rounded-md border">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Nome</TableHead>
                  <TableHead>Documento</TableHead>
                  <TableHead>Email</TableHead>
                  <TableHead>Telefone</TableHead>
                  <TableHead>Status</TableHead>
                  <TableHead className="w-[150px]"></TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {(state.suppliers || []).map((s: any) => (
                  <TableRow key={s.id}>
                    <TableCell className="font-medium">{s.name}</TableCell>
                    <TableCell>{s.document || '-'}</TableCell>
                    <TableCell>{s.email || '-'}</TableCell>
                    <TableCell>{s.phone || '-'}</TableCell>
                    <TableCell>
                      <Badge
                        variant="outline"
                        className={
                          s.status === 'Ativo'
                            ? 'bg-green-50 text-green-700 border-green-200'
                            : 'bg-slate-50 text-slate-700 border-slate-200'
                        }
                      >
                        {s.status || 'Ativo'}
                      </Badge>
                    </TableCell>
                    <TableCell>
                      <div className="flex items-center gap-2">
                        <Button
                          variant="ghost"
                          size="icon"
                          className="h-8 w-8"
                          onClick={() => setEditingSupplier(s)}
                        >
                          <Edit className="h-4 w-4" />
                        </Button>
                        {s.status !== 'Inativo' && (
                          <Button
                            variant="ghost"
                            size="icon"
                            className="h-8 w-8 text-amber-500 hover:text-amber-700 hover:bg-amber-50"
                            onClick={() => handleDeactivateSupplier(s)}
                            title="Desativar"
                          >
                            <Trash2 className="h-4 w-4" />
                          </Button>
                        )}
                      </div>
                    </TableCell>
                  </TableRow>
                ))}
                {(!state.suppliers || state.suppliers.length === 0) && (
                  <TableRow>
                    <TableCell colSpan={6} className="text-center py-8 text-muted-foreground">
                      Nenhum fornecedor encontrado.
                    </TableCell>
                  </TableRow>
                )}
              </TableBody>
            </Table>
          </div>
        </CardContent>
      </Card>

      <Card className="shadow-sm">
        <CardHeader className="py-4">
          <CardTitle className="text-sm">Categorias de Transações</CardTitle>
          <p className="text-xs text-muted-foreground">
            Adicione, edite ou remova as categorias usadas nos lançamentos financeiros. A edição
            atualiza também os lançamentos existentes.
          </p>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="flex gap-2">
            <Input
              value={newCategory}
              onChange={(e) => setNewCategory(e.target.value)}
              placeholder="Nova categoria..."
              className="h-8"
              onKeyDown={(e) => e.key === 'Enter' && handleAddCategory()}
            />
            <Button size="sm" onClick={handleAddCategory}>
              <Plus className="h-4 w-4" />
            </Button>
          </div>
          <div className="flex flex-wrap gap-2">
            {categories.map((c: string) =>
              editingCategory === c ? (
                <div
                  key={c}
                  className="flex items-center gap-1 bg-muted px-2 py-1 rounded text-sm border"
                >
                  <Input
                    autoFocus
                    value={editValue}
                    onChange={(e) => setEditValue(e.target.value)}
                    onKeyDown={(e) => {
                      if (e.key === 'Enter') saveEditCategory()
                      if (e.key === 'Escape') cancelEditCategory()
                    }}
                    className="h-6 w-40 text-sm"
                  />
                  <Check
                    className="h-3.5 w-3.5 text-green-600 cursor-pointer hover:scale-110 transition-transform"
                    onClick={saveEditCategory}
                  />
                  <X
                    className="h-3.5 w-3.5 text-muted-foreground cursor-pointer hover:scale-110 transition-transform"
                    onClick={cancelEditCategory}
                  />
                </div>
              ) : (
                <div
                  key={c}
                  className="flex items-center gap-1 bg-muted px-2 py-1 rounded text-sm border group"
                >
                  <span>{c}</span>
                  <div className="flex items-center gap-1 opacity-50 md:opacity-0 group-hover:opacity-100 transition-opacity">
                    <Edit2
                      className="h-3 w-3 cursor-pointer hover:scale-110 transition-transform"
                      onClick={() => startEditCategory(c)}
                    />
                    <Trash2
                      className="h-3 w-3 text-red-500 cursor-pointer hover:scale-110 transition-transform"
                      onClick={() => handleRemoveCategory(c)}
                    />
                  </div>
                </div>
              ),
            )}
            {categories.length === 0 && (
              <p className="text-sm text-muted-foreground">Nenhuma categoria cadastrada.</p>
            )}
          </div>
        </CardContent>
      </Card>

      <SupplierDialog
        open={!!editingSupplier}
        onOpenChange={(v: boolean) => !v && setEditingSupplier(null)}
        data={editingSupplier}
        onSave={(d: any) => updateItem('suppliers', editingSupplier.id, d)}
      />
      <SupplierDialog
        open={creatingSupplier}
        onOpenChange={setCreatingSupplier}
        onSave={(d: any) => addSupplier(d)}
      />
    </div>
  )
}
