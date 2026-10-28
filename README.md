# Torre de Controle Shopee — AJBorges

Painel web com mapa, KPIs e tabela dos veículos da operação Shopee. A posição
vem da API do Atlas, buscada pelo próprio Supabase a cada 15 minutos (sem
planilha e sem Apps Script).

A Torre usa o **Supabase do site da AJBorges**: os admins do site entram na
Torre com a mesma conta, e no futuro ela vai usar o mesmo cadastro de
motoristas e veículos. Por enquanto o código fica neste repositório e o painel
é aberto localmente (Live Server) apontando para o Supabase do site; mais
tarde ele vai ser copiado para dentro do site.

```
pg_cron (job torre-sincronizar-atlas, 15 min) ──> pg_net ──> Edge Function sincronizar-atlas ──> API do Atlas
                                                                 │ (tira o CPF)
                                                                 └──> RPC torre.aplicar_atlas ──> tabelas torre.*
Painel (HTML/CSS/JS) ── login do site ──> torre.v_painel (RLS: admin do site ou operador ativo)
```

> **Repositório público.** Nada de token, service role, TORRE_CRON_SECRET,
> e-mail, nome real, ID de planilha ou dado real aqui. A URL do projeto e a
> chave **pública** (anon/publishable) podem ir no `supabase-client.js`: quem
> protege os dados é o RLS.

## Regras de proteção do site

O banco do site está em produção, com motoristas e admins usando todo dia:

- **Tudo da Torre fica no schema `torre`** (tabelas, funções, view, policies).
  Nada é criado, alterado ou apagado no `public` nem em outro schema do site, e
  não há grant/revoke fora do `torre`. Do site, a Torre só **chama**
  `public.is_admin()` (sem alterar).
- **Secrets com nomes próprios.** O site usa `CRON_SECRET` e `ALLOWED_ORIGINS`;
  a Torre usa `TORRE_CRON_SECRET`, `ATLAS_TOKEN` e `ATLAS_CONTA` nas Edge
  Functions e `torre_url_sincronizar_atlas` / `torre_cron_secret` no Vault.
- **Jobs do pg_cron com nome `torre-…`.** O job do site (`limpar-recusados-lgpd`)
  não é tocado. Extensões só com `create extension if not exists`, nunca `drop`.
- O cadastro aberto (sign-up) já está desligado no site e continua assim.
- O teste `npm run test:sql` tira um retrato de tudo o que existe fora do
  schema `torre` (tabelas, colunas, funções, grants, policies, gatilhos, default
  privileges e linhas das tabelas do site), roda todos os arquivos SQL da Torre
  (e o `drop schema torre cascade`) e confere que o retrato não mudou.

## Arquivos

| Arquivo | O que é |
|---|---|
| `supabase/sql/passo01_atlas.sql` | Schema `torre`, tabelas, conversores, RPCs, view `v_painel`, permissões e RLS |
| `supabase/sql/passo01_conferencias.sql` | 15 conferências (um bloco por vez, terminam em `RESULTADO`) |
| `supabase/sql/passo02_agendamento.sql` | pg_cron + pg_net + Vault (sincronização e limpeza) |
| `supabase/sql/dados_exemplo.sql` | 30 veículos inventados para ver o painel antes da API real (gerado) |
| `supabase/sql/apagar_dados_exemplo.sql` | Apaga só os dados de exemplo |
| `supabase/functions/sincronizar-atlas/index.ts` | Edge Function que chama o Atlas |
| `HTML/login.html`, `HTML/index.html` | Login e painel |
| `CSS/style.css` | Estilos (claro/escuro, celular, Modo TV) |
| `JavaScript/supabase-client.js` | URL + chave pública, sessão, `escapeHtml`, preferências |
| `JavaScript/login.js`, `JavaScript/painel.js` | Login e painel |
| `testes/` | Amostras inventadas e testes (SQL no PGlite, função, painel com puppeteer) |

## Quem entra na Torre

`torre.eh_operador()` = `coalesce(public.is_admin(), false)` **ou** um registro
ativo em `torre.operadores`.

- **Admin do site** (papel `admin` ou `diretoria`): entra sem cadastro nenhum.
  A `public.is_admin()` do site lê `auth.jwt() -> 'app_metadata' ->> 'role'`.
  O `app_metadata` só é gravado pelo servidor; o `user_metadata` (que o próprio
  usuário consegue mudar) não vale.
- **Operador da Torre** (ex.: analista de frota): uma conta do Supabase Auth
  **sem** o papel de admin do site, mais um registro em `torre.operadores`
  (passo 3). Ele vê a Torre e não ganha nada no `public` (conferência C15).
- **Motorista do site:** tem conta no mesmo Auth, mas sem claim de admin e sem
  registro em `torre.operadores`: vê "Sem acesso à Torre de Controle".

**Como o admin do site faz login.** O login do site (`JavaScript/login.js`)
tem duas abas. Na aba **Administrador** o admin usa **e-mail e senha**, com
`supabase.auth.signInWithPassword({ email, password })` no Supabase Auth.
(Na aba Motorista o identificador é o CPF: o site procura o perfil pelo CPF e
entra com o e-mail do perfil ou `<cpf>@motorista.ajborges.com`.) A tela de
login da Torre usa o mesmo Supabase Auth, então **o admin entra na Torre com o
mesmo e-mail e a mesma senha do site**.

- Aberta localmente (Live Server), a Torre fica em outro endereço que o site,
  então as sessões são separadas: é preciso entrar nas duas.
- Quem não tem acesso vê "Sem acesso à Torre de Controle" e a sessão é
  encerrada só neste navegador (`signOut({ scope: 'local' })`), sem
  redirecionar para o site. O botão **Sair** da Torre também é local: não
  derruba a sessão da pessoa no site nem em outros aparelhos.

## Passo a passo

Tudo no painel do Supabase **do site**.

### 1. Liberar o schema `torre` na API
Project Settings → **Data API** → **Exposed schemas** → adicione `torre` →
Save. Sem isso o painel e a função não enxergam o schema (o login da Torre
avisa: "A Torre ainda não está liberada na API do Supabase").

Isso não abre nada: o `anon` não tem nem `usage` no schema, e o RLS continua
filtrando para quem está logado.

### 2. Rodar o passo 01 e as conferências
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
| C12 | admin do site (claim `admin` ou `diretoria`) lê a Torre sem estar em `torre.operadores` |
| C13 | motorista do site (sem claim, sem registro; `user_metadata` com "admin") não lê nada |
| C14 | anon nem enxerga o schema `torre` |
| C15 | operador da Torre que não é admin não lê nenhuma linha de `public.fichas_viagem`, `public.perfis` e `public.cadastros_agregados` |

Se o **C15** mostrar `LÊ n LINHAS`, quem libera é uma regra do **site** (a
Torre não dá grant nenhum no `public`): resolva com o responsável pelo site
antes de cadastrar operadores que não são admin.

### 3. Cadastrar o operador (quem não é admin do site)
Admins do site **não** precisam deste passo.

1. Authentication → Users → **Add user → Create new user**: e-mail, senha e
   **Auto Confirm User** marcado. **Não** dê o papel de admin do site (não
   mexa no `app_metadata`).
2. No SQL Editor (não salve com o e-mail real):
   ```sql
   insert into torre.operadores (user_id, nome, papel)
   select id, '<nome da pessoa>', 'operador' from auth.users where email = '<e-mail da pessoa>';
   ```
   `papel`: `operador` ou `gestao`. Para tirar o acesso:
   `update torre.operadores set ativo = false where user_id = (select id from auth.users where email = '<e-mail>');`

### 4. Carregar os dados de exemplo
SQL Editor → rode `supabase/sql/dados_exemplo.sql` (29 veículos ativos; ele
se recusa a rodar se já houver dados reais). Só grava em tabelas `torre.*`.

### 5. Abrir o painel local
1. Em `JavaScript/supabase-client.js` preencha `url` e `anonKey` com os **do
   site** (Project Settings → API Keys → chave **publishable/anon**. **Nunca**
   a secret/service role).
2. Abra `HTML/login.html` por um servidor local (ex.: extensão Live Server do
   VS Code) e entre com o e-mail e a senha de admin do site (ou do operador do
   passo 3).

### 6. Secrets e publicação da função
1. Gere o TORRE_CRON_SECRET no seu computador (não cole no chat nem no código):
   `node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"`
2. Edge Functions → **Secrets** → **adicione** `TORRE_CRON_SECRET`,
   `ATLAS_TOKEN` (o token Bearer) e `ATLAS_CONTA` (o valor do `X-AJBORGES-AUTH`).
   **Não altere nem apague** `CRON_SECRET` e `ALLOWED_ORIGINS`, que são do site.
   `SUPABASE_URL` e `SUPABASE_SERVICE_ROLE_KEY` já existem em toda função.
3. Edge Functions → **Deploy a new function → Via editor** → nome
   `sincronizar-atlas` → cole `supabase/functions/sincronizar-atlas/index.ts` → Deploy.
   (Confira antes que o site não tem uma função com esse nome.)
4. Na função → Details → **desligue "Verify JWT"** (quem protege é o `x-cron-secret`).
   Pela CLI seria: `npx supabase functions deploy sincronizar-atlas --no-verify-jwt --project-ref <ref>`
   (sempre com o nome da função, para não publicar outras).

A função chama as RPCs com os cabeçalhos `Content-Profile: torre` e
`Accept-Profile: torre`.

### 7. Vault e passo 02
1. No SQL Editor, cadastre os 2 segredos (veja a seção 0 do
   `passo02_agendamento.sql`) e depois apague a consulta do histórico do editor:
   `torre_url_sincronizar_atlas` = `https://<ref>.supabase.co/functions/v1/sincronizar-atlas`
   e `torre_cron_secret` = o mesmo valor do TORRE_CRON_SECRET.
   (Também dá para cadastrar pela tela Integrations → Vault.)
2. Rode `supabase/sql/passo02_agendamento.sql`. Ele cria a
   `torre.disparar_sincronizacao_atlas()` (lê os 2 segredos do Vault e manda o
   cabeçalho `x-cron-secret`) e os jobs `torre-sincronizar-atlas` (15 min) e
   `torre-limpar-historico` (03:17 de Brasília).
   - **Conferir:** `select jobid, jobname, schedule, active from cron.job;` (o `limpar-recusados-lgpd` do site continua lá, igual).
   - **Pausar:** `select cron.alter_job((select jobid from cron.job where jobname = 'torre-sincronizar-atlas'), active := false);`
   - **Reativar:** o mesmo com `active := true`.
   - **Trocar o intervalo:** mude `'*/15 * * * *'` no arquivo e rode de novo (ou `cron.alter_job(..., schedule := ...)`).

### 8. Primeira sincronização real
- Para não esperar o cron: `select torre.disparar_sincronizacao_atlas();`
- `select id, iniciado_em, http_status, recebidos, gravados, sem_placa, erro from torre.sincronizacao order by id desc limit 5;`
  (`erro` vazio = boa; `http_status` 401 = token/conta errados).
- Resposta HTTP da função: `select status_code, left(content::text, 300) from net._http_response order by created desc limit 5;`
  (se o site também usar o pg_net, as chamadas dele aparecem juntas).
- Logs: Edge Functions → sincronizar-atlas → Logs (só contagens, HTTP e request id).
- No painel, "Atualizado às" muda e os veículos de exemplo somem (ficam inativos).
  Compare o total com a planilha, que continua rodando em paralelo.

### 9. Apagar os dados de exemplo
SQL Editor → rode `supabase/sql/apagar_dados_exemplo.sql`.

## Desfazer tudo (sem afetar o site)

Na ordem, no Supabase do site:

1. **Jobs da Torre** (só os `torre-…`; nunca o `limpar-recusados-lgpd`):
   ```sql
   select cron.unschedule('torre-sincronizar-atlas');
   select cron.unschedule('torre-limpar-historico');
   ```
2. **Schema da Torre.** Primeiro confira se algo FORA do `torre` depende dele
   (só leitura; o esperado é **nenhuma linha**):
   ```sql
   select distinct pg_describe_object(d.classid, d.objid, d.objsubid) as fora_do_torre
     from pg_depend d
    where d.refobjid in (select oid from pg_class where relnamespace = 'torre'::regnamespace
                         union all select oid from pg_proc where pronamespace = 'torre'::regnamespace
                         union all select oid from pg_type where typnamespace = 'torre'::regnamespace)
      and d.deptype = 'n'
      and pg_describe_object(d.classid, d.objid, d.objsubid) not like '%torre.%';
   ```
   Sem linhas, apague:
   ```sql
   drop schema torre cascade;
   ```
   Se aparecer alguma linha (ex.: uma view do site que passou a usar a Torre),
   **pare**: o `cascade` apagaria aquilo também. Resolva com o responsável pelo site.
3. **Segredos do Vault da Torre:**
   ```sql
   delete from vault.secrets where name in ('torre_url_sincronizar_atlas', 'torre_cron_secret');
   ```
4. **Função:** Edge Functions → `sincronizar-atlas` → Delete function.
5. **Secrets da função:** Edge Functions → Secrets → apague `TORRE_CRON_SECRET`,
   `ATLAS_TOKEN` e `ATLAS_CONTA` (**não** `CRON_SECRET` nem `ALLOWED_ORIGINS`).
6. **Data API:** tire `torre` de Exposed schemas.
7. **Contas:** as contas criadas só para a Torre (operadores do passo 3) podem
   ser apagadas em Authentication → Users. As dos admins e motoristas são do
   site: não apague.

Não desative o pg_cron nem o pg_net: o site usa.

## Tamanho do histórico

Agora as tabelas da Torre ocupam espaço no banco do site. Medido no teste
(`testes/sql.test.mjs`): **~125 bytes por posição** com os índices (no
Supabase, 64 bits, conte ~140). No pior caso cada veículo gera uma posição nova
a cada 15 min (96/dia):

| Veículos | Por mês, sem limpeza | Fixo com 15 dias de retenção |
|---|---|---|
| 100 | ~40 MB | ~20 MB |
| 300 | ~120 MB | ~60 MB |

O resto (retrato atual, paradas, sincronizações de 90 dias) fica abaixo de
10 MB. A limpeza roda 1x por dia (03:17 de Brasília); os dias de retenção ficam
em `torre.parametros`. Confira o espaço livre do plano do site em
Project Settings → Usage.

## Quando o painel for para dentro do site

- No mesmo endereço do site, o supabase-js usa a mesma chave de sessão
  (`sb-<ref>-auth-token`): quem já entrou no site entra direto na Torre.
- Mantenha o `signOut({ scope: 'local' })` da Torre.
- Toda consulta continua com `.schema('torre')`.

## Testes (sem dados reais)

```bash
npm install
npm test                 # tudo
npm run test:sql         # passo 01, conferências, proteção do site, exemplo, limpeza, passo 02, tamanho
npm run test:funcao      # função com fetch simulado (200, 401, JSON inválido, vazio, timeout)
npm run test:painel      # puppeteer em 1366, 1920 e 390 px (usa o Chrome instalado)
```

- O SQL roda no PGlite simulando o Supabase do site: papéis e grants padrão,
  `auth.jwt()`, a `public.is_admin()` igual à do site (lê o JWT) e três tabelas
  do site com RLS e linhas.
- As conferências são conferidas pelo texto exato do `Esperado:` de cada bloco.
- A função é testada com um PostgREST simulado que exige `Content-Profile` e
  `Accept-Profile` = `torre`; o painel, com um Supabase simulado que exige os
  mesmos cabeçalhos em toda consulta.
- Se mudar `testes/amostra_atlas.json`, regenere o exemplo: `node testes/gerar_dados_exemplo.mjs`.
- Capturas de tela ficam em `testes/capturas/` (fora do git).
  `TORRE_TESTE_REDE=1 npm run test:painel` usa fontes e mapa de verdade.
