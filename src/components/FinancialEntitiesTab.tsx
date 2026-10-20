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

  // Tipos de Despesa (Item 2)
  const [newExpenseType, setNewExpenseType] = useState('')
  const [editingExpenseType, setEditingExpenseType] = useState<string | null>(null)
  const [editExpenseTypeValue, setEditExpenseTypeValue] = useState('')

  // Contas Bancárias (Relocadas para cá - Item 2)
  const [newBankAccount, setNewBankAccount] = useState('')
  const [editingBankAccount, setEditingBankAccount] = useState<string | null>(null)
  const [editBankAccountValue, setEditBankAccountValue] = useState('')

  const categories: string[] = (state.settings?.transactionCategories as string[]) || []
  const expenseTypes: string[] = (state.settings?.expenseTypes as string[]) || [
    'Aluguel',
    'Bolsa de Estágio',
    'Contabilidade',
    'Custas e Emolumentos',
    'Energia Elétrica',
    'Impostos e Tributos',
    'Internet e Telefonia',
    'Marketing e Publicidade',
    'Material de Escritório',
    'Pró-labore',
    'Retirada de Lucros',
    'Seguros',
    'Software e Tecnologia',
    'Tarifas Bancárias',
    'Outros',
  ]
  const bankAccounts: string[] = (state.settings?.bankAccounts as string[]) || [
    'ASAAS',
    'SICOOB',
    'CAIXA',
    'PESSOAL',
  ]

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

  // --- Handlers para Tipos de Despesa ---
  const handleAddExpenseType = () => {
    const trimmed = newExpenseType.trim()
    if (!trimmed || expenseTypes.includes(trimmed)) return
    updateItem('settings', state.settings.id, {
      expenseTypes: [...expenseTypes, trimmed].sort((a, b) => a.localeCompare(b, 'pt-BR')),
    })
    setNewExpenseType('')
  }

  const handleRemoveExpenseType = (typeToRemove: string) => {
    updateItem('settings', state.settings.id, {
      expenseTypes: expenseTypes.filter((t) => t !== typeToRemove),
    })
  }

  const startEditExpenseType = (typeToEdit: string) => {
    setEditingExpenseType(typeToEdit)
    setEditExpenseTypeValue(typeToEdit)
  }

  const cancelEditExpenseType = () => {
    setEditingExpenseType(null)
    setEditExpenseTypeValue('')
  }

  const saveEditExpenseType = () => {
    if (!editingExpenseType) return
    const trimmed = editExpenseTypeValue.trim()
    if (!trimmed) {
      toast({ title: 'Erro', description: 'Nome inválido.', variant: 'destructive' })
      return
    }
    if (trimmed === editingExpenseType) {
      cancelEditExpenseType()
      return
    }
    if (expenseTypes.includes(trimmed)) {
      toast({
        title: 'Erro',
        description: 'Já existe um tipo de despesa com esse nome.',
        variant: 'destructive',
      })
      return
    }
    updateItem('settings', state.settings.id, {
      expenseTypes: expenseTypes
        .map((t) => (t === editingExpenseType ? trimmed : t))
        .sort((a, b) => a.localeCompare(b, 'pt-BR')),
    })
    // Propaga renomeação se já houver lançamentos com essa categoria
    renameType('transactions', 'category', editingExpenseType, trimmed)
    toast({ title: 'Sucesso', description: 'Tipo de despesa atualizado.' })
    cancelEditExpenseType()
  }

  // --- Handlers para Contas Bancárias ---
  const handleAddBankAccount = () => {
    const trimmed = newBankAccount.trim()
    if (!trimmed || bankAccounts.includes(trimmed)) return
    updateItem('settings', state.settings.id, {
      bankAccounts: [...bankAccounts, trimmed].sort((a, b) => a.localeCompare(b, 'pt-BR')),
    })
    setNewBankAccount('')
  }

  const handleRemoveBankAccount = (accToRemove: string) => {
    updateItem('settings', state.settings.id, {
      bankAccounts: bankAccounts.filter((a) => a !== accToRemove),
    })
  }

  const startEditBankAccount = (accToEdit: string) => {
    setEditingBankAccount(accToEdit)
    setEditBankAccountValue(accToEdit)
  }

  const cancelEditBankAccount = () => {
    setEditingBankAccount(null)
    setEditBankAccountValue('')
  }

  const saveEditBankAccount = () => {
    if (!editingBankAccount) return
    const trimmed = editBankAccountValue.trim()
    if (!trimmed) {
      toast({ title: 'Erro', description: 'Nome de conta inválido.', variant: 'destructive' })
      return
    }
    if (trimmed === editingBankAccount) {
      cancelEditBankAccount()
      return
    }
    if (bankAccounts.includes(trimmed)) {
      toast({
        title: 'Erro',
        description: 'Já existe uma conta bancária com esse nome.',
        variant: 'destructive',
      })
      return
    }
    updateItem('settings', state.settings.id, {
      bankAccounts: bankAccounts
        .map((a) => (a === editingBankAccount ? trimmed : a))
        .sort((a, b) => a.localeCompare(b, 'pt-BR')),
    })
    renameType('transactions', 'bankAccount', editingBankAccount, trimmed)
    toast({ title: 'Sucesso', description: 'Conta bancária atualizada.' })
    cancelEditBankAccount()
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
                  <TableHead>Grupo</TableHead>
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
                    <TableCell>
                      {s.group_name ? (
                        <Badge
                          variant="secondary"
                          className="bg-blue-50 text-blue-700 border border-blue-200 font-normal text-xs"
                        >
                          {s.group_name}
                        </Badge>
                      ) : (
                        <span className="text-muted-foreground text-xs">—</span>
                      )}
                    </TableCell>
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
                          <Edit2 className="h-4 w-4" />
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
                    <TableCell colSpan={7} className="text-center py-8 text-muted-foreground">
                      Nenhum fornecedor encontrado.
                    </TableCell>
                  </TableRow>
                )}
              </TableBody>
            </Table>
          </div>
        </CardContent>
      </Card>

      {/* Editor de Contas Bancárias (Relocado de Opções Gerais para Financeiro) */}
      <Card className="shadow-sm">
        <CardHeader className="py-4">
          <CardTitle className="text-sm">Contas Bancárias</CardTitle>
          <p className="text-xs text-muted-foreground">
            Gerencie as contas bancárias disponíveis nos lançamentos, parcelamentos e conciliação
            (ex: ASAAS, SICOOB, CAIXA, etc).
          </p>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="flex gap-2">
            <Input
              value={newBankAccount}
              onChange={(e) => setNewBankAccount(e.target.value)}
              placeholder="Nova conta bancária..."
              className="h-8 max-w-sm"
              onKeyDown={(e) => e.key === 'Enter' && handleAddBankAccount()}
            />
            <Button size="sm" onClick={handleAddBankAccount}>
              <Plus className="h-4 w-4 mr-1" /> Adicionar
            </Button>
          </div>
          <div className="flex flex-wrap gap-2">
            {bankAccounts.map((acc: string) =>
              editingBankAccount === acc ? (
                <div
                  key={acc}
                  className="flex items-center gap-1 bg-muted px-2 py-1 rounded text-sm border"
                >
                  <Input
                    autoFocus
                    value={editBankAccountValue}
                    onChange={(e) => setEditBankAccountValue(e.target.value)}
                    onKeyDown={(e) => {
                      if (e.key === 'Enter') saveEditBankAccount()
                      if (e.key === 'Escape') cancelEditBankAccount()
                    }}
                    className="h-6 w-40 text-sm"
                  />
                  <Check
                    className="h-3.5 w-3.5 text-green-600 cursor-pointer hover:scale-110 transition-transform"
                    onClick={saveEditBankAccount}
                  />
                  <X
                    className="h-3.5 w-3.5 text-muted-foreground cursor-pointer hover:scale-110 transition-transform"
                    onClick={cancelEditBankAccount}
                  />
                </div>
              ) : (
                <div
                  key={acc}
                  className="flex items-center gap-1 bg-muted px-2 py-1 rounded text-sm border group"
                >
                  <span>{acc}</span>
                  <div className="flex items-center gap-1 opacity-50 md:opacity-0 group-hover:opacity-100 transition-opacity">
                    <Edit2
                      className="h-3 w-3 cursor-pointer hover:scale-110 transition-transform"
                      onClick={() => startEditBankAccount(acc)}
                    />
                    <Trash2
                      className="h-3 w-3 text-red-500 cursor-pointer hover:scale-110 transition-transform"
                      onClick={() => handleRemoveBankAccount(acc)}
                    />
                  </div>
                </div>
              ),
            )}
            {bankAccounts.length === 0 && (
              <p className="text-sm text-muted-foreground">Nenhuma conta cadastrada.</p>
            )}
          </div>
        </CardContent>
      </Card>

      {/* Editor de Tipo de Despesa (Item 2: cria/renomeia/exclui tipos que alimentam os lançamentos) */}
      <Card className="shadow-sm">
        <CardHeader className="py-4">
          <CardTitle className="text-sm">Tipos de Despesa</CardTitle>
          <p className="text-xs text-muted-foreground">
            Gerencie os tipos de despesas do escritório (ex: Aluguel, Bolsa de Estágio, Impostos e
            Tributos, etc). Alimenta o dropdown &quot;Tipo de Despesa&quot; ao registrar despesas do
            escritório.
          </p>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="flex gap-2">
            <Input
              value={newExpenseType}
              onChange={(e) => setNewExpenseType(e.target.value)}
              placeholder="Novo tipo de despesa..."
              className="h-8 max-w-sm"
              onKeyDown={(e) => e.key === 'Enter' && handleAddExpenseType()}
            />
            <Button size="sm" onClick={handleAddExpenseType}>
              <Plus className="h-4 w-4 mr-1" /> Adicionar
            </Button>
          </div>
          <div className="flex flex-wrap gap-2">
            {expenseTypes.map((t: string) =>
              editingExpenseType === t ? (
                <div
                  key={t}
                  className="flex items-center gap-1 bg-muted px-2 py-1 rounded text-sm border"
                >
                  <Input
                    autoFocus
                    value={editExpenseTypeValue}
                    onChange={(e) => setEditExpenseTypeValue(e.target.value)}
                    onKeyDown={(e) => {
                      if (e.key === 'Enter') saveEditExpenseType()
                      if (e.key === 'Escape') cancelEditExpenseType()
                    }}
                    className="h-6 w-44 text-sm"
                  />
                  <Check
                    className="h-3.5 w-3.5 text-green-600 cursor-pointer hover:scale-110 transition-transform"
                    onClick={saveEditExpenseType}
                  />
                  <X
                    className="h-3.5 w-3.5 text-muted-foreground cursor-pointer hover:scale-110 transition-transform"
                    onClick={cancelEditExpenseType}
                  />
                </div>
              ) : (
                <div
                  key={t}
                  className="flex items-center gap-1 bg-muted px-2 py-1 rounded text-sm border group"
                >
                  <span>{t}</span>
                  <div className="flex items-center gap-1 opacity-50 md:opacity-0 group-hover:opacity-100 transition-opacity">
                    <Edit2
                      className="h-3 w-3 cursor-pointer hover:scale-110 transition-transform"
                      onClick={() => startEditExpenseType(t)}
                    />
                    <Trash2
                      className="h-3 w-3 text-red-500 cursor-pointer hover:scale-110 transition-transform"
                      onClick={() => handleRemoveExpenseType(t)}
                    />
                  </div>
                </div>
              ),
            )}
            {expenseTypes.length === 0 && (
              <p className="text-sm text-muted-foreground">Nenhum tipo de despesa cadastrado.</p>
            )}
          </div>
        </CardContent>
      </Card>

      {/* Editor de Categorias Gerais / Honorários */}
      <Card className="shadow-sm">
        <CardHeader className="py-4">
          <CardTitle className="text-sm">Categorias Gerais de Transações</CardTitle>
          <p className="text-xs text-muted-foreground">
            Categorias padronizadas para honorários e custas judiciais. A edição atualiza também os
            lançamentos existentes.
          </p>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="flex gap-2">
            <Input
              value={newCategory}
              onChange={(e) => setNewCategory(e.target.value)}
              placeholder="Nova categoria..."
              className="h-8 max-w-sm"
              onKeyDown={(e) => e.key === 'Enter' && handleAddCategory()}
            />
            <Button size="sm" onClick={handleAddCategory}>
              <Plus className="h-4 w-4 mr-1" /> Adicionar
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
        existingGroups={Array.from(
          new Set((state.suppliers || []).map((s: any) => s.group_name).filter(Boolean)),
        )}
        onSave={(d: any) => updateItem('suppliers', editingSupplier.id, d)}
      />
      <SupplierDialog
        open={creatingSupplier}
        onOpenChange={setCreatingSupplier}
        existingGroups={Array.from(
          new Set((state.suppliers || []).map((s: any) => s.group_name).filter(Boolean)),
        )}
        onSave={(d: any) => addSupplier(d)}
      />
    </div>
  )
}
