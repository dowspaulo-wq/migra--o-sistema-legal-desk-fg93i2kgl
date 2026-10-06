FROM node:20-alpine AS builder

WORKDIR /app

# Argumentos de build passados pelo EasyPanel/Docker
# O Vite insere essas variáveis estaticamente nos arquivos JS compilados
ARG VITE_SUPABASE_URL
ARG VITE_SUPABASE_PUBLISHABLE_KEY

ENV VITE_SUPABASE_URL=$VITE_SUPABASE_URL
ENV VITE_SUPABASE_PUBLISHABLE_KEY=$VITE_SUPABASE_PUBLISHABLE_KEY
ENV NODE_ENV=production

# Habilita o Corepack e ativa o pnpm
RUN corepack enable && corepack prepare pnpm@latest --activate

# Copia manifestos de dependências primeiro para aproveitar cache de camadas
COPY package.json pnpm-lock.yaml ./

# Instala todas as dependências necessárias para o build usando pnpm
RUN pnpm install --frozen-lockfile

# Copia todo o código-fonte
COPY . .

# Executa o build de produção Vite -> pasta dist/
RUN pnpm run build

# -------------------------------------------------------------
# Estágio final: Nginx Alpine ultraleve para servir o frontend estático
# -------------------------------------------------------------
FROM nginx:1.27-alpine AS runner

# Remove a página de boas-vindas padrão do Nginx
RUN rm -rf /usr/share/nginx/html/*

# Copia configuração customizada de roteamento SPA (HTML5 History API)
COPY docs/migracao-fase3/nginx.conf /etc/nginx/conf.d/default.conf

# Copia os artefatos compilados do estágio anterior
COPY --from=builder /app/dist /usr/share/nginx/html

# Copia e concede permissão de execução ao script de entrypoint para gerar env.js em runtime
COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh

# Porta HTTP exposta
EXPOSE 80

# Checagem de saúde simples do container
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
  CMD wget --quiet --tries=1 --spider http://127.0.0.1:80/ || exit 1

ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["nginx", "-g", "daemon off;"]
