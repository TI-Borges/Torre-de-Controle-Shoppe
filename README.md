# Torre de Controle Shopee — AJBorges

Painel web com mapa, KPIs e tabela dos veículos da operação Shopee. A posição
vem da API do Atlas, buscada pelo próprio Supabase a cada 15 minutos (sem
planilha e sem Apps Script).

```
pg_cron (15 min) ──> pg_net ──> Edge Function sincronizar-atlas ──> API do Atlas
                                        │ (tira o CPF)
                                        └──> RPC aplicar_atlas ──> tabelas
Painel (HTML/CSS/JS) ── login ──> v_painel (RLS: só operador ativo)
```

> **Repositório público.** Nada de token, service role, CRON_SECRET, e-mail,
> nome real, ID de planilha ou dado real aqui. A URL do projeto e a chave
> **pública** (anon/publishable) podem ir no `supabase-client.js`: quem protege
> os dados é o RLS.

## Arquivos

| Arquivo | O que é |
|---|---|
| `supabase/sql/passo01_atlas.sql` | Tabelas, conversores, RPCs, view `v_painel`, permissões e RLS |
| `supabase/sql/passo01_conferencias.sql` | 11 conferências (um bloco por vez, terminam em `RESULTADO`) |
| `supabase/sql/passo02_agendamento.sql` | pg_cron + pg_net + Vault (sincronização e limpeza) |
| `supabase/sql/dados_exemplo.sql` | 30 veículos inventados para ver o painel antes da API real (gerado) |
| `supabase/sql/apagar_dados_exemplo.sql` | Apaga só os dados de exemplo |
| `supabase/functions/sincronizar-atlas/index.ts` | Edge Function que chama o Atlas |
| `HTML/login.html`, `HTML/index.html` | Login e painel |
| `CSS/style.css` | Estilos (claro/escuro, celular, Modo TV) |
| `JavaScript/supabase-client.js` | URL + chave pública, sessão, `escapeHtml`, preferências |
| `JavaScript/login.js`, `JavaScript/painel.js` | Login e painel |
| `testes/` | Amostras inventadas e testes (SQL no PGlite, função, painel com puppeteer) |

## Passo a passo

### 1. Criar o projeto
1. supabase.com → **New project** (por enquanto na organização pessoal).
   Região **South America (São Paulo)**. Guarde a senha do banco no gerenciador de senhas.
2. **Desligar o cadastro aberto:** Authentication → Sign In / Providers →
   desmarque **Allow new users to sign up** → Save. Assim só entra quem a gestão
   criar em Authentication → Users.

### 2. Rodar o SQL e as conferências
1. SQL Editor → cole e rode `supabase/sql/passo01_atlas.sql`.
2. Abra `supabase/sql/passo01_conferencias.sql` e rode **um bloco por vez**
   (do `begin;` ao `rollback;`). Cada bloco termina com o erro
   `RESULTADO (nada foi salvo): ...`: o texto tem de ser igual à linha
   `Esperado:` do bloco. Nada fica gravado.

| Bloco | Prova que |
|---|---|
| C1, C2 | anon e usuário logado que não é operador não leem nada |
| C3 | o operador lê tudo, e da tabela `operadores` só a própria linha |
| C4, C5 | ninguém grava pela API (nem se promove, nem chama as RPCs) |
| C6 | a trava dos 50% (e da resposta vazia) não altera nada e registra o erro |
| C7 | a posição só entra no histórico quando muda |
| C8 | a regra do ETA dá os 3 casos (ETA / Erro API Atlas / Sem SM) |
| C9 | nenhum CPF fica gravado, nem dentro do `bruto` |
| C10, C11 | item sem placa, placa repetida, objeto único e conversor de datas |

### 3. Criar o primeiro operador
1. Authentication → Users → **Add user → Create new user**: e-mail, senha e
   **Auto Confirm User** marcado.
2. No SQL Editor (não salve com o e-mail real):
   ```sql
   insert into public.operadores (user_id, nome, papel)
   select id, '<nome da pessoa>', 'gestao' from auth.users where email = '<e-mail da pessoa>';
   ```
   `papel`: `operador` ou `gestao`. Para tirar o acesso: `update public.operadores set ativo = false where ...`.

### 4. Carregar os dados de exemplo e abrir o painel
1. SQL Editor → rode `supabase/sql/dados_exemplo.sql` (29 veículos ativos;
   ele se recusa a rodar se já houver dados reais).
2. Em `JavaScript/supabase-client.js` preencha `url` e `anonKey`
   (Project Settings → API Keys → chave **publishable/anon**. **Nunca** a secret/service role).
3. Abra `HTML/login.html` por um servidor local (ex.: extensão Live Server do
   VS Code) e entre com o operador do passo 3.

### 5. Publicar a função e cadastrar os secrets
1. Gere o CRON_SECRET no seu computador (não cole no chat nem no código):
   `node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"`
2. Edge Functions → **Secrets** → crie `ATLAS_TOKEN` (o token Bearer),
   `ATLAS_CONTA` (o valor do `X-AJBORGES-AUTH`) e `CRON_SECRET`.
   `SUPABASE_URL` e `SUPABASE_SERVICE_ROLE_KEY` já existem em toda função.
3. Edge Functions → **Deploy a new function → Via editor** → nome
   `sincronizar-atlas` → cole `supabase/functions/sincronizar-atlas/index.ts` → Deploy.
4. Na função → Details → **desligue "Verify JWT"** (quem protege é o `x-cron-secret`).
   Pela CLI seria: `npx supabase functions deploy sincronizar-atlas --no-verify-jwt --project-ref <ref>`.

### 6. Cadastrar o Vault e o agendamento
1. No SQL Editor, cadastre os 2 segredos (veja a seção 0 do
   `passo02_agendamento.sql`) e depois apague a consulta do histórico do editor:
   `torre_url_sincronizar_atlas` = `https://<ref>.supabase.co/functions/v1/sincronizar-atlas`
   e `torre_cron_secret` = o mesmo valor do CRON_SECRET.
   (Também dá para cadastrar pela tela Integrations → Vault.)
2. Rode `supabase/sql/passo02_agendamento.sql`.
   - **Pausar:** `select cron.alter_job((select jobid from cron.job where jobname = 'torre-sincronizar-atlas'), active := false);`
   - **Reativar:** o mesmo com `active := true`.
   - **Trocar o intervalo:** mude `'*/15 * * * *'` no arquivo e rode de novo (ou `cron.alter_job(..., schedule := ...)`).

### 7. Conferir a primeira sincronização real
- Para não esperar o cron: `select public.disparar_sincronizacao_atlas();`
- `select id, iniciado_em, http_status, recebidos, gravados, sem_placa, erro from public.sincronizacao order by id desc limit 5;`
  (`erro` vazio = boa; `http_status` 401 = token/conta errados).
- Resposta HTTP da função: `select status_code, left(content::text, 300) from net._http_response order by created desc limit 5;`
- Logs: Edge Functions → sincronizar-atlas → Logs (só contagens, HTTP e request id).
- No painel, "Atualizado às" muda e os veículos de exemplo somem (ficam inativos).
  Compare o total com a planilha, que continua rodando em paralelo.

### 8. Apagar os dados de exemplo
SQL Editor → rode `supabase/sql/apagar_dados_exemplo.sql`.

## Transferir para a organização da empresa

Project Settings → General → **Transfer project**. Na transferência continuam
iguais: o endereço (ref) do projeto, as chaves, o banco, os usuários do Auth,
os secrets da função, o Vault e os agendamentos. **Nada no código ou no SQL
precisa ser refeito**, porque nada depende da conta.

Antes/depois de transferir:
- é preciso ser dono (Owner) da organização pessoal e membro da organização da empresa;
  a tela de transferência lista os pré-requisitos (ex.: integrações conectadas);
- se a organização da empresa estiver no plano grátis, ela tem limite de projetos
  gratuitos ativos; a cobrança passa a ser da empresa;
- convide a equipe na organização da empresa e tire acessos pessoais que não
  fizerem mais sentido; como boa prática, troque a senha do banco e o CRON_SECRET
  (secret da função **e** `vault.update_secret`).

Se em vez de transferir for criado **outro** projeto na empresa, aí sim é refazer
os passos 1 a 8, recriar os operadores e trocar `url`/`anonKey` no
`supabase-client.js` e a URL no Vault.

## Tamanho do histórico (plano grátis: 500 MB)

Medido no teste (`testes/sql.test.mjs`): **~125 bytes por posição** com os
índices (no Supabase, 64 bits, conte ~140). No pior caso cada veículo gera uma
posição nova a cada 15 min (96/dia):

| Veículos | Por mês, sem limpeza | Fixo com 15 dias de retenção |
|---|---|---|
| 100 | ~40 MB | ~20 MB |
| 300 | ~120 MB | ~60 MB |

O resto (retrato atual, paradas, sincronizações de 90 dias) fica abaixo de
10 MB. **Cabe com folga nos 500 MB.** A limpeza roda 1x por dia (03:17 de
Brasília); os dias de retenção ficam em `public.parametros`.

## Testes (sem dados reais)

```bash
npm install
npm test                 # tudo
npm run test:sql         # passo 01, conferências, exemplo, limpeza, passo 02, tamanho
npm run test:funcao      # função com fetch simulado (200, 401, JSON inválido, vazio, timeout)
npm run test:painel      # puppeteer em 1366, 1920 e 390 px (usa o Chrome instalado)
```

- O SQL roda no PGlite com os papéis e grants padrão do Supabase simulados.
- As conferências são conferidas pelo texto exato do `Esperado:` de cada bloco.
- Se mudar `testes/amostra_atlas.json`, regenere o exemplo: `node testes/gerar_dados_exemplo.mjs`.
- Capturas de tela ficam em `testes/capturas/` (fora do git).
  `TORRE_TESTE_REDE=1 npm run test:painel` usa fontes e mapa de verdade.
