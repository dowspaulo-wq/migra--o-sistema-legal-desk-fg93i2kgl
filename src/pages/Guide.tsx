import React, { useState, useEffect } from 'react'
import { Link } from 'react-router-dom'
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import {
  Scale,
  LayoutDashboard,
  Users,
  Briefcase,
  CheckSquare,
  Calendar,
  UserCircle,
  ChevronLeft,
  ChevronRight,
  Sparkles,
  ShieldAlert,
  ArrowRight,
  Info,
  CheckCircle2,
  Lock,
  Eye,
  KeyRound,
  FileText,
  Clock,
  Gift,
  HelpCircle,
  Layers,
  Search,
  Plus,
  Compass,
} from 'lucide-react'

interface Slide {
  id: string
  badge: string
  title: string
  subtitle: string
  icon: React.ComponentType<{ className?: string }>
  content: React.ReactNode
}

export default function Guide(): React.ReactElement {
  const [currentSlide, setCurrentSlide] = useState(0)

  // Teclas de seta para navegar entre os slides
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'ArrowRight') {
        setCurrentSlide((prev) => (prev < slides.length - 1 ? prev + 1 : prev))
      } else if (e.key === 'ArrowLeft') {
        setCurrentSlide((prev) => (prev > 0 ? prev - 1 : prev))
      }
    }
    window.addEventListener('keydown', handleKeyDown)
    return () => window.removeEventListener('keydown', handleKeyDown)
  }, [])

  const nextSlide = () => {
    if (currentSlide < slides.length - 1) {
      setCurrentSlide((prev) => prev + 1)
    }
  }

  const prevSlide = () => {
    if (currentSlide > 0) {
      setCurrentSlide((prev) => prev - 1)
    }
  }

  const goToSlide = (index: number) => {
    setCurrentSlide(index)
  }

  const slides: Slide[] = [
    // Slide 1: Boas-vindas
    {
      id: 'welcome',
      badge: 'Onboarding DPSjur',
      title: 'Bem-vindo ao DPSjur!',
      subtitle: 'Plataforma integrada de gestão jurídica e rotina forense para a nossa equipe.',
      icon: Scale,
      content: (
        <div className="space-y-6">
          <div className="p-5 rounded-xl bg-gradient-to-r from-primary/10 via-primary/5 to-transparent border border-primary/20">
            <h3 className="text-lg font-bold text-slate-800 flex items-center gap-2 mb-2">
              <Sparkles className="h-5 w-5 text-primary" />O que é o DPSjur?
            </h3>
            <p className="text-slate-600 leading-relaxed text-sm md:text-base">
              O <strong>DPSjur</strong> é o sistema oficial de gestão do nosso escritório de
              advocacia. Ele foi desenvolvido para centralizar clientes, processos judiciais,
              prazos, tarefas operacionais e a rotina forense, garantindo agilidade, controle
              rigoroso de prazos e excelência no atendimento.
            </p>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
            <div className="p-4 rounded-lg bg-card border shadow-sm space-y-2">
              <div className="h-9 w-9 rounded-md bg-blue-100 text-blue-700 flex items-center justify-center font-bold">
                1
              </div>
              <h4 className="font-semibold text-sm text-slate-800">Organização Centralizada</h4>
              <p className="text-xs text-muted-foreground leading-normal">
                Toda a carteira de clientes, acervo de processos e histórico de atuações em um único
                lugar seguro.
              </p>
            </div>

            <div className="p-4 rounded-lg bg-card border shadow-sm space-y-2">
              <div className="h-9 w-9 rounded-md bg-emerald-100 text-emerald-700 flex items-center justify-center font-bold">
                2
              </div>
              <h4 className="font-semibold text-sm text-slate-800">Controle Rigoroso de Prazos</h4>
              <p className="text-xs text-muted-foreground leading-normal">
                Foco total no cumprimento de diligências, petições, recursos e audiências sem riscos
                de perda de prazo.
              </p>
            </div>

            <div className="p-4 rounded-lg bg-card border shadow-sm space-y-2">
              <div className="h-9 w-9 rounded-md bg-amber-100 text-amber-700 flex items-center justify-center font-bold">
                3
              </div>
              <h4 className="font-semibold text-sm text-slate-800">Trabalho Colaborativo</h4>
              <p className="text-xs text-muted-foreground leading-normal">
                Distribuição clara de tarefas por responsável, anotações internas e acompanhamento
                em tempo real.
              </p>
            </div>
          </div>

          <div className="flex items-start gap-3 p-3.5 bg-blue-50/80 border border-blue-200 rounded-lg text-blue-900 text-xs md:text-sm">
            <Info className="h-5 w-5 shrink-0 text-blue-600 mt-0.5" />
            <div>
              <strong>Objetivo deste guia:</strong> Apresentar a você, colaborador, as
              funcionalidades essenciais da sua rotina diária no sistema com foco nas ferramentas
              ativas para o seu perfil.
            </div>
          </div>
        </div>
      ),
    },

    // Slide 2: Como Navegar (Sidebar e Perfil Colaborador)
    {
      id: 'navigation',
      badge: 'Navegação e Estrutura',
      title: 'Como Navegar no Sistema',
      subtitle: 'Conheça o menu lateral e as permissões atribuídas ao perfil Colaborador.',
      icon: Compass,
      content: (
        <div className="space-y-6">
          <div className="grid grid-cols-1 md:grid-cols-2 gap-5">
            <div className="space-y-3">
              <h3 className="font-semibold text-sm text-slate-800 flex items-center gap-2">
                <CheckCircle2 className="h-4 w-4 text-emerald-600" />
                Seções disponíveis para o Colaborador
              </h3>
              <div className="space-y-2">
                <div className="p-3 bg-card border rounded-lg flex items-center justify-between">
                  <div className="flex items-center gap-3">
                    <LayoutDashboard className="h-4 w-4 text-primary" />
                    <div>
                      <p className="font-medium text-xs md:text-sm">Dashboard</p>
                      <p className="text-[11px] text-muted-foreground">
                        Visão geral do escritório e suas tarefas
                      </p>
                    </div>
                  </div>
                  <Badge variant="secondary" className="text-[10px]">
                    Início
                  </Badge>
                </div>

                <div className="p-3 bg-card border rounded-lg flex items-center justify-between">
                  <div className="flex items-center gap-3">
                    <Users className="h-4 w-4 text-primary" />
                    <div>
                      <p className="font-medium text-xs md:text-sm">Clientes</p>
                      <p className="text-[11px] text-muted-foreground">
                        Cadastro PF e PJ, contatos e histórico
                      </p>
                    </div>
                  </div>
                  <Badge variant="outline" className="text-[10px]">
                    Carteira
                  </Badge>
                </div>

                <div className="p-3 bg-card border rounded-lg flex items-center justify-between">
                  <div className="flex items-center gap-3">
                    <Briefcase className="h-4 w-4 text-primary" />
                    <div>
                      <p className="font-medium text-xs md:text-sm">Processos</p>
                      <p className="text-[11px] text-muted-foreground">
                        Acompanhamento e subprocessos
                      </p>
                    </div>
                  </div>
                  <Badge variant="outline" className="text-[10px]">
                    Judicial
                  </Badge>
                </div>

                <div className="p-3 bg-card border rounded-lg flex items-center justify-between">
                  <div className="flex items-center gap-3">
                    <CheckSquare className="h-4 w-4 text-primary" />
                    <div>
                      <p className="font-medium text-xs md:text-sm">Tarefas</p>
                      <p className="text-[11px] text-muted-foreground">
                        Gestão diária de atividades e prazos
                      </p>
                    </div>
                  </div>
                  <Badge variant="outline" className="text-[10px]">
                    Operação
                  </Badge>
                </div>

                <div className="p-3 bg-card border rounded-lg flex items-center justify-between">
                  <div className="flex items-center gap-3">
                    <FileText className="h-4 w-4 text-primary" />
                    <div>
                      <p className="font-medium text-xs md:text-sm">Petições</p>
                      <p className="text-[11px] text-muted-foreground">
                        Modelos básicos e gerador de documentos
                      </p>
                    </div>
                  </div>
                  <Badge variant="outline" className="text-[10px]">
                    Documentos
                  </Badge>
                </div>
              </div>
            </div>

            <div className="space-y-3">
              <h3 className="font-semibold text-sm text-slate-800 flex items-center gap-2">
                <Lock className="h-4 w-4 text-amber-600" />
                Regras de Acesso e Permissões do Perfil
              </h3>
              <div className="p-4 rounded-xl bg-amber-50/70 border border-amber-200/80 space-y-3 text-xs md:text-sm text-amber-950">
                <div className="flex items-start gap-2">
                  <ShieldAlert className="h-4 w-4 text-amber-700 shrink-0 mt-0.5" />
                  <div>
                    <strong>Financeiro Restrito:</strong> Os módulos Financeiro e Dashboard
                    Financeiro ficam ocultos para o colaborador padrão (
                    <code className="bg-amber-100/70 px-1 py-0.5 rounded text-[11px]">
                      canViewFinance: false
                    </code>
                    ).
                  </div>
                </div>

                <div className="flex items-start gap-2">
                  <ShieldAlert className="h-4 w-4 text-amber-700 shrink-0 mt-0.5" />
                  <div>
                    <strong>Agenda e Administração:</strong> A aba de Agenda completa e os módulos
                    Acessos, Backups e Configurações avançadas são de gestão exclusiva da
                    administração.
                  </div>
                </div>

                <div className="flex items-start gap-2">
                  <ShieldAlert className="h-4 w-4 text-amber-700 shrink-0 mt-0.5" />
                  <div>
                    <strong>Abas Desativadas:</strong> As seções antigas de <em>Logs</em> e{' '}
                    <em>Modelos externos</em> foram desativadas/escondidas para manter o fluxo
                    enxuto e seguro.
                  </div>
                </div>
              </div>

              <div className="p-3 rounded-lg bg-slate-50 border text-xs text-slate-600 flex items-center gap-2">
                <Eye className="h-4 w-4 text-slate-500 shrink-0" />
                <span>
                  O menu lateral adapta-se automaticamente, exibindo apenas o que você precisa para
                  trabalhar com foco e produtividade.
                </span>
              </div>
            </div>
          </div>
        </div>
      ),
    },

    // Slide 3: Dashboard / Início
    {
      id: 'dashboard',
      badge: 'Visão Geral',
      title: 'Dashboard / Painel Inicial',
      subtitle:
        'Seu ponto de partida diário: métricas, alertas urgentes e distribuição de demandas.',
      icon: LayoutDashboard,
      content: (
        <div className="space-y-5">
          <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
            <div className="p-4 rounded-xl bg-card border shadow-sm">
              <span className="text-xs font-semibold text-primary uppercase tracking-wider block mb-1">
                Indicadores Rápidos
              </span>
              <p className="text-xs text-muted-foreground leading-relaxed">
                Cards com o total de <strong>Processos Ativos</strong>,{' '}
                <strong>Clientes Cadastrados</strong> e o atalho direto para{' '}
                <strong>Minhas Tarefas Pendentes</strong>.
              </p>
            </div>

            <div className="p-4 rounded-xl bg-card border shadow-sm">
              <span className="text-xs font-semibold text-destructive uppercase tracking-wider block mb-1">
                Alertas de Protocolo
              </span>
              <p className="text-xs text-muted-foreground leading-relaxed">
                Aviso destacado em vermelho sempre que houver tarefas no status{' '}
                <strong>Aguarda protocolo</strong>, garantindo ação prioritária imediata.
              </p>
            </div>

            <div className="p-4 rounded-xl bg-card border shadow-sm">
              <span className="text-xs font-semibold text-slate-700 uppercase tracking-wider block mb-1">
                Tarefas por Responsável
              </span>
              <p className="text-xs text-muted-foreground leading-relaxed">
                Painel visual retrátil que consolida pendências, tarefas em atualização, concluídas
                e alertas de atividades em atraso.
              </p>
            </div>
          </div>

          <div className="p-4 rounded-xl bg-slate-50 border space-y-3">
            <h4 className="text-sm font-semibold text-slate-800 flex items-center gap-2">
              <Layers className="h-4 w-4 text-primary" />
              Gráficos de Distribuição no Dashboard
            </h4>
            <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-4 gap-3 text-xs">
              <div className="p-2.5 bg-white rounded border">
                <span className="font-semibold block text-slate-800 mb-1">
                  Status dos Processos
                </span>
                <p className="text-muted-foreground">
                  Distribuição percentual (Em andamento, Concluído, Suspenso, etc.).
                </p>
              </div>
              <div className="p-2.5 bg-white rounded border">
                <span className="font-semibold block text-slate-800 mb-1">
                  Clientes por Colaborador
                </span>
                <p className="text-muted-foreground">
                  Volume de clientes sob responsabilidade de cada membro da equipe.
                </p>
              </div>
              <div className="p-2.5 bg-white rounded border">
                <span className="font-semibold block text-slate-800 mb-1">
                  Processos por Colaborador
                </span>
                <p className="text-muted-foreground">
                  Carga de trabalho ativa atribuída a cada advogado/colaborador.
                </p>
              </div>
              <div className="p-2.5 bg-white rounded border">
                <span className="font-semibold block text-slate-800 mb-1">
                  Clientes por Captação
                </span>
                <p className="text-muted-foreground">
                  Canais de captação de clientes (Indicação, Redes, etc.).
                </p>
              </div>
            </div>
          </div>

          <div className="p-3 bg-emerald-50 border border-emerald-200 rounded-lg text-emerald-900 text-xs flex items-center gap-2">
            <CheckCircle2 className="h-4 w-4 text-emerald-600 shrink-0" />
            <span>
              <strong>Dica de rotina:</strong> Comece o dia abrindo o link "Minhas Tarefas
              Pendentes" no Dashboard para organizar sua fila de trabalho.
            </span>
          </div>
        </div>
      ),
    },

    // Slide 4: Clientes
    {
      id: 'clients',
      badge: 'Módulo de Clientes',
      title: 'Gestão Completa de Clientes',
      subtitle: 'Cadastro padronizado PF/PJ, contatos, integração de CEP e preferências.',
      icon: Users,
      content: (
        <div className="space-y-5">
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div className="p-4 rounded-xl bg-card border shadow-sm space-y-3">
              <h4 className="text-sm font-semibold text-slate-800 flex items-center gap-2">
                <Plus className="h-4 w-4 text-primary" />
                Novo Cliente & Edição
              </h4>
              <ul className="text-xs text-muted-foreground space-y-2 list-disc pl-4 leading-relaxed">
                <li>
                  <strong>Pessoa Física (PF) ou Pessoa Jurídica (PJ):</strong> máscaras automáticas
                  de CPF (<code className="text-[11px]">000.000.000-00</code>) ou CNPJ (
                  <code className="text-[11px]">00.000.000/0000-00</code>).
                </li>
                <li>
                  <strong>Busca automática por CEP:</strong> ao digitar 8 dígitos do CEP, Rua,
                  Bairro, Cidade e UF são preenchidos via ViaCEP.
                </li>
                <li>
                  <strong>Campos essenciais:</strong> Nome Completo, E-mail, Celular com DDD, Status
                  (Ativo / Baixado), Responsável e Captação.
                </li>
                <li>
                  <strong>Cliente Especial (Estrela):</strong> marque clientes estratégicos com a
                  estrela dourada para destaque visual imediato.
                </li>
              </ul>
            </div>

            <div className="p-4 rounded-xl bg-card border shadow-sm space-y-3">
              <h4 className="text-sm font-semibold text-slate-800 flex items-center gap-2">
                <Gift className="h-4 w-4 text-pink-500" />
                Aniversários e Calendário
              </h4>
              <p className="text-xs text-muted-foreground leading-relaxed">
                Para clientes Pessoa Física (PF), o campo de <strong>
                  Data de Nascimento
                </strong>{' '}
                permite o acompanhamento de aniversários.
              </p>
              <div className="p-3 bg-pink-50 border border-pink-200 rounded-lg text-pink-900 text-xs space-y-1.5">
                <p className="font-semibold flex items-center gap-1.5">
                  <CheckCircle2 className="h-3.5 w-3.5 text-pink-600" />
                  Opção: "Não exibir aniversário no calendário"
                </p>
                <p className="text-pink-800 leading-normal">
                  Se marcada no cadastro do cliente, o aniversário não aparecerá na agenda do
                  escritório, respeitando pedidos específicos de clientes ou discrição.
                </p>
              </div>
              <div className="text-xs text-muted-foreground pt-1">
                <strong>Pesquisa Avançada:</strong> filtre por Nome, Documento, Tipo (PF/PJ),
                Status, E-mail, Telefone, Responsável e Cliente Especial.
              </div>
            </div>
          </div>

          <div className="p-3 bg-slate-50 border rounded-lg text-xs text-slate-700 flex items-center justify-between">
            <span className="flex items-center gap-2">
              <Search className="h-4 w-4 text-slate-500" />
              Busca rápida no topo da lista por nome ou documento, com alternância de exibição entre{' '}
              <strong>Lista</strong> e <strong>Grade</strong>.
            </span>
          </div>
        </div>
      ),
    },

    // Slide 5: Processos
    {
      id: 'cases',
      badge: 'Módulo de Processos',
      title: 'Acompanhamento Processual',
      subtitle: 'Controle de processos judiciais, juízo, partes, subprocessos e publicações.',
      icon: Briefcase,
      content: (
        <div className="space-y-5">
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div className="p-4 rounded-xl bg-card border shadow-sm space-y-3">
              <h4 className="text-sm font-semibold text-slate-800 flex items-center gap-2">
                <Scale className="h-4 w-4 text-primary" />
                Cadastro e Informações do Processo
              </h4>
              <ul className="text-xs text-muted-foreground space-y-2 list-disc pl-4 leading-relaxed">
                <li>
                  <strong>Número do Processo:</strong> numeração padrão CNJ unificada (
                  <code className="text-[11px]">0000000-00.0000.0.00.0000</code>).
                </li>
                <li>
                  <strong>Juízo & Comarca:</strong> Tribunal/Sistema (PJe, Projudi, Eproc, etc.),
                  Vara, Comarca e Estado (UF).
                </li>
                <li>
                  <strong>Partes:</strong> Cliente vinculado, Posição da parte e identificação da
                  Parte Adversa.
                </li>
                <li>
                  <strong>Alertas do Processo:</strong> marcações como <em>Segredo de Justiça</em>,{' '}
                  <em>Cobrar astreites</em> ou <em>Litigância de má-fé</em>.
                </li>
              </ul>
            </div>

            <div className="p-4 rounded-xl bg-card border shadow-sm space-y-3">
              <h4 className="text-sm font-semibold text-slate-800 flex items-center gap-2">
                <Clock className="h-4 w-4 text-primary" />
                Publicações & Rotina Forense Manual
              </h4>
              <div className="p-3 bg-blue-50 border border-blue-200 rounded-lg text-blue-900 text-xs space-y-1.5">
                <p className="font-semibold flex items-center gap-1.5">
                  <Info className="h-3.5 w-3.5 text-blue-600" />
                  Publicações Controladas Manualmente
                </p>
                <p className="text-blue-800 leading-normal">
                  No DPSjur, o acompanhamento de movimentações e publicações é{' '}
                  <strong>alimentado e controlado diretamente pela equipe</strong>. Não dependemos
                  de capturas automáticas externas: cada intimação deve ter sua tarefa
                  correspondente cadastrada com prazo e responsável.
                </p>
              </div>
              <ul className="text-xs text-muted-foreground space-y-1.5 list-disc pl-4">
                <li>
                  <strong>Subprocessos vinculados:</strong> Recursos, Cartas Precatórias e
                  Incidentes vinculados ao processo principal.
                </li>
                <li>
                  <strong>Visibilidade Restrita:</strong> processos estratégicos confidenciais
                  marcados com cadeado são restritos aos administradores.
                </li>
              </ul>
            </div>
          </div>

          <div className="p-3 bg-slate-50 border rounded-lg text-xs text-slate-700 flex items-center gap-2">
            <CheckCircle2 className="h-4 w-4 text-emerald-600 shrink-0" />
            <span>
              Na tela de <strong>Detalhes do Processo</strong>, você encontra abas dedicadas para
              Informações, Subprocessos, Tarefas vinculadas, Agenda e Documentos gerados.
            </span>
          </div>
        </div>
      ),
    },

    // Slide 6: Tarefas & Atualizações
    {
      id: 'tasks',
      badge: 'Módulo de Tarefas',
      title: 'Gestão de Tarefas e Prazos',
      subtitle: 'Criação, categorização, fluxos de trabalho e a categoria especial ATUALIZAÇÕES.',
      icon: CheckSquare,
      content: (
        <div className="space-y-5">
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div className="p-4 rounded-xl bg-card border shadow-sm space-y-3">
              <h4 className="text-sm font-semibold text-slate-800 flex items-center gap-2">
                <Plus className="h-4 w-4 text-primary" />
                Criando e Gerenciando uma Tarefa
              </h4>
              <ul className="text-xs text-muted-foreground space-y-2 list-disc pl-4 leading-relaxed">
                <li>
                  <strong>Título claro e descritivo:</strong> ex.: "Protocolar contestação no
                  processo X".
                </li>
                <li>
                  <strong>Data de Vencimento e Prioridade:</strong> Baixa, Média, Alta ou Urgente
                  (com código de cores visual).
                </li>
                <li>
                  <strong>Vínculo:</strong> associe ao Cliente e/ou ao Processo específico para
                  histórico automático.
                </li>
                <li>
                  <strong>Responsável:</strong> atribua ao colaborador encarregado da elaboração ou
                  cumprimento.
                </li>
                <li>
                  <strong>Conclusão:</strong> botão "Concluir" registra o colaborador que finalizou
                  e a data da entrega.
                </li>
              </ul>
            </div>

            <div className="p-4 rounded-xl bg-card border shadow-sm space-y-3">
              <h4 className="text-sm font-semibold text-slate-800 flex items-center gap-2">
                <Layers className="h-4 w-4 text-amber-600" />
                Categorias e a regra de ATUALIZAÇÕES
              </h4>
              <div className="p-3 bg-amber-50 border border-amber-200 rounded-lg text-amber-950 text-xs space-y-1.5">
                <p className="font-semibold flex items-center gap-1.5">
                  <ShieldAlert className="h-4 w-4 text-amber-700" />
                  ATUALIZAÇÕES (Centralizadas no usuário Mestre)
                </p>
                <p className="text-amber-800 leading-normal">
                  As tarefas de <strong>ATUALIZAÇÕES</strong> (alimentação e checagem periódica do
                  andamento de processos) são{' '}
                  <strong>centralizadas no usuário Mestre / Administrador</strong>.
                </p>
                <p className="text-amber-800 leading-normal">
                  Colaboradores não devem concluir tarefas sob responsabilidade direta do
                  administrador — o sistema possui trava de segurança para preservar a governança.
                </p>
              </div>

              <div className="grid grid-cols-2 gap-2 text-xs pt-1">
                <div className="p-2 bg-slate-50 border rounded">
                  <span className="font-semibold block text-slate-700">PRAZOS / PETIÇÕES</span>
                  <span className="text-[11px] text-muted-foreground">
                    Peticionamento, iniciais e manifestações
                  </span>
                </div>
                <div className="p-2 bg-slate-50 border rounded">
                  <span className="font-semibold block text-slate-700">RECURSOS</span>
                  <span className="text-[11px] text-muted-foreground">
                    Apelações, agravos e embargos
                  </span>
                </div>
              </div>
            </div>
          </div>

          <div className="p-3 bg-red-50 border border-red-200 rounded-lg text-red-900 text-xs flex items-center gap-2">
            <ShieldAlert className="h-4 w-4 text-red-600 shrink-0" />
            <span>
              <strong>Atenção aos Atrasados:</strong> Tarefas vencidas aparecem sinalizadas em
              vermelho no Dashboard e no topo dos filtros de pesquisa para resolução imediata.
            </span>
          </div>
        </div>
      ),
    },

    // Slide 7: Agenda
    {
      id: 'agenda',
      badge: 'Módulo de Agenda',
      title: 'Agenda, Prazos e Eventos',
      subtitle: 'Compromissos, audiências, reuniões e aniversários de clientes.',
      icon: Calendar,
      content: (
        <div className="space-y-5">
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div className="p-4 rounded-xl bg-card border shadow-sm space-y-3">
              <h4 className="text-sm font-semibold text-slate-800 flex items-center gap-2">
                <Calendar className="h-4 w-4 text-primary" />
                Compromissos e Audiências
              </h4>
              <ul className="text-xs text-muted-foreground space-y-2 list-disc pl-4 leading-relaxed">
                <li>
                  <strong>Tipos de Compromisso:</strong> Audiência, Reunião com Cliente, Diligência,
                  Perícia e Prazos.
                </li>
                <li>
                  <strong>Modalidade:</strong> Presencial (com endereço/fórum) ou Virtual (com link
                  de videoconferência).
                </li>
                <li>
                  <strong>Horário e Responsável:</strong> data, hora marcada e advogado encarregado.
                </li>
                <li>
                  <strong>Vínculo:</strong> processo e cliente relacionados diretamente na linha do
                  tempo.
                </li>
              </ul>
            </div>

            <div className="p-4 rounded-xl bg-card border shadow-sm space-y-3">
              <h4 className="text-sm font-semibold text-slate-800 flex items-center gap-2">
                <Gift className="h-4 w-4 text-pink-500" />
                Aniversários de Clientes PF
              </h4>
              <p className="text-xs text-muted-foreground leading-relaxed">
                A agenda projeta automaticamente os aniversários de{' '}
                <strong>Clientes Pessoa Física</strong> no dia correspondente de cada ano,
                permitindo estreitar o relacionamento e enviar mensagens de felicitações.
              </p>
              <div className="p-3 bg-pink-50 border border-pink-200 rounded-lg text-pink-900 text-xs space-y-1">
                <p className="font-semibold">Privacidade respeitada:</p>
                <p className="text-pink-800 leading-normal">
                  Se a opção <em>"Não exibir aniversário no calendário"</em> estiver ativa no
                  cadastro do cliente, a data não será exibida na agenda pública.
                </p>
              </div>
            </div>
          </div>

          <div className="p-3.5 bg-slate-50 border rounded-lg text-xs md:text-sm text-slate-700 flex items-center justify-between flex-wrap gap-2">
            <span className="flex items-center gap-2">
              <Info className="h-4 w-4 text-primary shrink-0" />
              Na tela do processo e no Dashboard, os compromissos do dia são destacados com acesso
              rápido para conclusão ou reagendamento.
            </span>
          </div>
        </div>
      ),
    },

    // Slide 8: Perfil & Segurança
    {
      id: 'profile',
      badge: 'Perfil e Segurança',
      title: 'Meu Perfil, Senha e Acesso',
      subtitle: 'Foto de perfil, recuperação de senha e política de inativação de contas.',
      icon: UserCircle,
      content: (
        <div className="space-y-5">
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div className="p-4 rounded-xl bg-card border shadow-sm space-y-3">
              <h4 className="text-sm font-semibold text-slate-800 flex items-center gap-2">
                <UserCircle className="h-4 w-4 text-primary" />
                Foto e Identificação
              </h4>
              <ul className="text-xs text-muted-foreground space-y-2 list-disc pl-4 leading-relaxed">
                <li>
                  <strong>Atualizar foto de perfil:</strong> acesse o menu do seu avatar no canto
                  superior direito e clique em <em>"Alterar Foto"</em> ou vá em{' '}
                  <em>"Configurações &gt; Meu Perfil"</em>.
                </li>
                <li>
                  <strong>Fallback automático:</strong> caso não envie uma foto, o sistema exibe
                  automaticamente as <strong>iniciais do seu nome</strong> em um círculo com a cor
                  de identidade do seu usuário.
                </li>
                <li>
                  <strong>Cor do usuário:</strong> cada colaborador possui uma cor única que
                  identifica visualmente suas tarefas e cards no sistema.
                </li>
              </ul>
            </div>

            <div className="p-4 rounded-xl bg-card border shadow-sm space-y-3">
              <h4 className="text-sm font-semibold text-slate-800 flex items-center gap-2">
                <KeyRound className="h-4 w-4 text-primary" />
                Troca e Recuperação de Senha
              </h4>
              <ul className="text-xs text-muted-foreground space-y-2 list-disc pl-4 leading-relaxed">
                <li>
                  <strong>Esqueceu a senha?</strong> na tela inicial de login, clique no link{' '}
                  <em>"Esqueceu a senha?"</em>, digite seu e-mail cadastrado e você receberá um link
                  seguro de recuperação.
                </li>
                <li>
                  <strong>Redefinição:</strong> o link permite definir uma nova senha (mínimo de 8
                  caracteres) com verificação de confirmação em tempo real.
                </li>
                <li>
                  <strong>Boas práticas:</strong> nunca compartilhe sua senha corporativa nem
                  utilize senhas simples ou sequenciais.
                </li>
              </ul>
            </div>
          </div>

          <div className="p-4 bg-amber-50 border border-amber-200 rounded-xl text-amber-950 text-xs md:text-sm space-y-1.5">
            <h5 className="font-bold flex items-center gap-2 text-amber-900">
              <ShieldAlert className="h-4 w-4 text-amber-700 shrink-0" />
              Aviso Importante: Usuários Inativos
            </h5>
            <p className="text-amber-800 leading-relaxed text-xs">
              Por motivos de segurança e conformidade, colaboradores que forem desativados pela
              administração perdem imediatamente o acesso ao sistema. Tentativas de login com conta
              inativa resultam no bloqueio automático do acesso. Mantenha seus contatos e demandas
              sempre em dia!
            </p>
          </div>
        </div>
      ),
    },

    // Slide 9: Dicas Finais & Conclusão
    {
      id: 'tips',
      badge: 'Encerramento',
      title: 'Dicas Rápidas de Sucesso',
      subtitle: 'Boas práticas para um trabalho produtivo e de alto padrão no DPSjur.',
      icon: Sparkles,
      content: (
        <div className="space-y-6">
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div className="p-4 rounded-xl bg-card border shadow-sm space-y-2">
              <div className="flex items-center gap-2 text-primary font-semibold text-sm">
                <CheckCircle2 className="h-4 w-4" />
                1. Registre tudo no processo
              </div>
              <p className="text-xs text-muted-foreground leading-relaxed">
                Qualquer petição protocolada, telefonema relevante ou documento recebido deve ter
                anotação interna ou tarefa concluída vinculada ao processo correspondente.
              </p>
            </div>

            <div className="p-4 rounded-xl bg-card border shadow-sm space-y-2">
              <div className="flex items-center gap-2 text-primary font-semibold text-sm">
                <CheckCircle2 className="h-4 w-4" />
                2. Checagem matinal de pendências
              </div>
              <p className="text-xs text-muted-foreground leading-relaxed">
                Ao iniciar o expediente, abra o Dashboard e filtre a lista por suas tarefas
                pendentes e prazos da semana. Isso evita urgências desnecessárias no final do dia.
              </p>
            </div>

            <div className="p-4 rounded-xl bg-card border shadow-sm space-y-2">
              <div className="flex items-center gap-2 text-primary font-semibold text-sm">
                <CheckCircle2 className="h-4 w-4" />
                3. Dados do cliente completos
              </div>
              <p className="text-xs text-muted-foreground leading-relaxed">
                Sempre preencha CEP, telefone com DDD e CPF/CNPJ com as máscaras corretas. Cadastros
                completos poupam tempo da equipe jurídica e de atendimento.
              </p>
            </div>

            <div className="p-4 rounded-xl bg-card border shadow-sm space-y-2">
              <div className="flex items-center gap-2 text-primary font-semibold text-sm">
                <CheckCircle2 className="h-4 w-4" />
                4. Comunicação e dúvidas
              </div>
              <p className="text-xs text-muted-foreground leading-relaxed">
                Em caso de dúvidas sobre prioridades, prazos fatais ou atualizações, consulte sempre
                o usuário Mestre / Administrador do escritório.
              </p>
            </div>
          </div>

          <div className="p-6 rounded-xl bg-gradient-to-r from-primary/10 via-primary/5 to-slate-50 border border-primary/20 text-center space-y-3">
            <div className="mx-auto w-12 h-12 rounded-full bg-primary/10 text-primary flex items-center justify-center">
              <Scale className="h-6 w-6" />
            </div>
            <h3 className="text-lg font-bold text-slate-800">
              Excelente trabalho e boas-vindas à nossa equipe!
            </h3>
            <p className="text-sm text-muted-foreground max-w-xl mx-auto">
              O DPSjur foi feito para facilitar sua rotina e permitir que você foque no que faz de
              melhor: o direito e a defesa dos nossos clientes.
            </p>
            <div className="pt-2">
              <Button asChild className="font-medium shadow">
                <Link to="/">
                  Ir para o Dashboard
                  <ArrowRight className="h-4 w-4 ml-2" />
                </Link>
              </Button>
            </div>
          </div>
        </div>
      ),
    },
  ]

  const slide = slides[currentSlide]
  const SlideIcon = slide.icon

  return (
    <div className="max-w-5xl mx-auto space-y-6 pb-12">
      {/* Top Header */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 border-b pb-4">
        <div>
          <div className="flex items-center gap-2">
            <div className="p-2 rounded-lg bg-primary/10 text-primary">
              <HelpCircle className="h-5 w-5" />
            </div>
            <div>
              <h1 className="text-2xl md:text-3xl font-bold tracking-tight text-slate-800">
                Guia do Colaborador
              </h1>
              <p className="text-xs md:text-sm text-muted-foreground">
                Manual interativo de apresentação das funcionalidades do sistema DPSjur
              </p>
            </div>
          </div>
        </div>

        {/* Counter and quick jump */}
        <div className="flex items-center gap-3 self-end sm:self-center">
          <Badge
            variant="outline"
            className="px-3 py-1 font-semibold text-xs border-primary/30 text-primary bg-primary/5"
          >
            Slide {currentSlide + 1} de {slides.length}
          </Badge>
          <div className="flex items-center gap-1">
            <Button
              variant="outline"
              size="icon"
              className="h-8 w-8"
              onClick={prevSlide}
              disabled={currentSlide === 0}
              title="Slide anterior (Seta para a esquerda)"
            >
              <ChevronLeft className="h-4 w-4" />
            </Button>
            <Button
              variant="outline"
              size="icon"
              className="h-8 w-8"
              onClick={nextSlide}
              disabled={currentSlide === slides.length - 1}
              title="Próximo slide (Seta para a direita)"
            >
              <ChevronRight className="h-4 w-4" />
            </Button>
          </div>
        </div>
      </div>

      {/* Main Slide Card */}
      <Card className="shadow-md border border-slate-200/80 overflow-hidden">
        {/* Slide Header */}
        <CardHeader className="bg-slate-50/70 border-b border-slate-100 pb-5">
          <div className="flex items-start justify-between gap-4">
            <div className="space-y-1">
              <Badge variant="secondary" className="text-[11px] font-semibold mb-2">
                {slide.badge}
              </Badge>
              <CardTitle className="text-xl md:text-2xl font-bold text-slate-800 flex items-center gap-2.5">
                <SlideIcon className="h-6 w-6 text-primary shrink-0" />
                {slide.title}
              </CardTitle>
              <CardDescription className="text-xs md:text-sm text-slate-600">
                {slide.subtitle}
              </CardDescription>
            </div>
          </div>
        </CardHeader>

        {/* Slide Body */}
        <CardContent className="p-6 md:p-8 min-h-[420px] flex flex-col justify-between">
          <div className="flex-1">{slide.content}</div>

          {/* Bottom Slide Navigation Bar */}
          <div className="pt-8 mt-6 border-t border-slate-100 flex flex-col sm:flex-row items-center justify-between gap-4">
            {/* Dots */}
            <div className="flex items-center gap-1.5 flex-wrap justify-center">
              {slides.map((s, idx) => (
                <button
                  key={s.id}
                  onClick={() => goToSlide(idx)}
                  className={`h-2.5 rounded-full transition-all ${
                    idx === currentSlide
                      ? 'w-7 bg-primary'
                      : 'w-2.5 bg-slate-200 hover:bg-slate-300'
                  }`}
                  title={`Ir para: ${s.title}`}
                  aria-label={`Slide ${idx + 1}`}
                />
              ))}
            </div>

            {/* Prev / Next Buttons */}
            <div className="flex items-center gap-2">
              <Button
                variant="outline"
                size="sm"
                onClick={prevSlide}
                disabled={currentSlide === 0}
                className="gap-1 text-xs"
              >
                <ChevronLeft className="h-3.5 w-3.5" />
                Anterior
              </Button>

              {currentSlide < slides.length - 1 ? (
                <Button size="sm" onClick={nextSlide} className="gap-1 text-xs font-semibold">
                  Próximo
                  <ChevronRight className="h-3.5 w-3.5" />
                </Button>
              ) : (
                <Button
                  size="sm"
                  asChild
                  className="gap-1 text-xs font-semibold bg-emerald-600 hover:bg-emerald-700"
                >
                  <Link to="/">
                    Concluir Guia
                    <CheckCircle2 className="h-3.5 w-3.5 ml-1" />
                  </Link>
                </Button>
              )}
            </div>
          </div>
        </CardContent>
      </Card>

      {/* Helpful keyboard hint */}
      <p className="text-center text-xs text-muted-foreground flex items-center justify-center gap-2">
        <span>Dica: Use as setas do teclado</span>
        <kbd className="px-1.5 py-0.5 text-[10px] bg-slate-100 border border-slate-300 rounded font-mono">
          ←
        </kbd>
        <span>e</span>
        <kbd className="px-1.5 py-0.5 text-[10px] bg-slate-100 border border-slate-300 rounded font-mono">
          →
        </kbd>
        <span>para navegar entre os slides.</span>
      </p>
    </div>
  )
}
