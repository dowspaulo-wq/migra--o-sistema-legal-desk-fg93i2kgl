# Projeto Criado com o Skip

Este projeto foi criado de ponta a ponta com o [Skip](https://goskip.dev).

## 🚀 Stack Tecnológica

- **React 19** - Biblioteca JavaScript para construção de interfaces
- **Vite** - Build tool extremamente rápida
- **TypeScript** - Superset tipado do JavaScript
- **Shadcn UI** - Componentes reutilizáveis e acessíveis
- **Tailwind CSS** - Framework CSS utility-first
- **React Router** - Roteamento para aplicações React
- **React Hook Form** - Gerenciamento de formulários performático
- **Zod** - Validação de schemas TypeScript-first
- **Recharts** - Biblioteca de gráficos para React

## 📋 Pré-requisitos

- Node.js 18+
- npm

## 🔧 Instalação

```bash
npm install
```

## 💻 Scripts Disponíveis

### Desenvolvimento

```bash
# Iniciar servidor de desenvolvimento
npm start
# ou
npm run dev
```

Abre a aplicação em modo de desenvolvimento em [http://localhost:5173](http://localhost:5173).

### Build

```bash
# Build para produção
npm run build

# Build para desenvolvimento
npm run build:dev
```

Gera os arquivos otimizados para produção na pasta `dist/`.

### Preview

```bash
# Visualizar build de produção localmente
npm run preview
```

Permite visualizar a build de produção localmente antes do deploy.

### Linting e Formatação

```bash
# Executar linter
npm run lint

# Executar linter e corrigir problemas automaticamente
npm run lint:fix

# Formatar código com Oxfmt
npm run format
```

## 📁 Estrutura do Projeto

```
.
├── src/              # Código fonte da aplicação
├── public/           # Arquivos estáticos
├── docs/             # Documentação de migração e infraestrutura VPS
│   ├── backup-fase6/ # Fase 6: Sistema de backup automático, Google Drive e alertas
│   ├── asaas-integracao/ # Integração com Asaas (Edge Functions no VPS)
│   ├── pos-migracao/ # Scripts operacionais pós-migração
│   └── migracao-fase4/ # Kit oficial de migração para o Supabase no VPS
├── dist/             # Build de produção (gerado)
├── node_modules/     # Dependências (gerado)
└── package.json      # Configurações e dependências do projeto
```

## 🛡️ Kits de Infraestrutura e Operação no VPS (Hostinger KVM 1)

O sistema SBJur/DPSjur opera em infraestrutura própria no VPS Hostinger via EasyPanel e Docker. Abaixo estão os kits de automação e runbooks disponíveis:

- **Fase 6 — Backup Automático e Cópia Externa (`docs/backup-fase6/`):**
  - **[Runbook Completo (00-README.md)](docs/backup-fase6/00-README.md)** — Passo a passo ilustrado para o usuário Douglas;
  - Dump diário automático às 03:00 via `pg_dump` no container PostgreSQL;
  - Política de retenção inteligente: 7 dias diários, 30 dias de domingo (semanal), 1 ano de dia 1º (mensal);
  - Sincronização em nuvem externa no **Google Drive** do escritório via `rclone`;
  - Notificação diária de sucesso e alertas de falha por **e-mail** via Gmail SMTP;
  - Script de teste de restauração em banco temporário paralelo (`sbjur_restore_test`) sem tocar nos dados de produção.
- **Fase Asaas — Edge Functions no VPS (`docs/asaas-integracao/`):**
  - Sincronização de cobranças e clientes com a API oficial do Asaas.
- **Fase 4 — Migração Supabase Self-Hosted (`docs/migracao-fase4/`):**
  - DDL, políticas RLS, credenciais GoTrue e importação de dados.

## 🎨 Componentes UI

Este template inclui uma biblioteca completa de componentes Shadcn UI baseados em Radix UI:

- Accordion
- Alert Dialog
- Avatar
- Button
- Checkbox
- Dialog
- Dropdown Menu
- Form
- Input
- Label
- Select
- Switch
- Tabs
- Toast
- Tooltip
- E muito mais...

## 📝 Ferramentas de Qualidade de Código

- **TypeScript**: Tipagem estática
- **Oxlint**: Linter extremamente rápido
- **Oxfmt**: Formatação automática de código

## 🔄 Workflow de Desenvolvimento

1. Instale as dependências: `npm install`
2. Inicie o servidor de desenvolvimento: `npm start`
3. Faça suas alterações
4. Verifique o código: `npm run lint`
5. Formate o código: `npm run format`
6. Crie a build: `npm run build`
7. Visualize a build: `npm run preview`

## 📦 Build e Deploy

Para criar uma build otimizada para produção:

```bash
npm run build
```

Os arquivos otimizados serão gerados na pasta `dist/` e estarão prontos para deploy.
