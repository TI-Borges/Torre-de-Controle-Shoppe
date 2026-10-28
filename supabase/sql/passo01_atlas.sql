-- =============================================================================
-- Torre de Controle Shopee - Passo 01: tabelas do Atlas, RPC, painel e acesso
-- =============================================================================
-- Rodar no SQL Editor do Supabase (projeto da Torre de Controle, NÃO o do site).
-- Pode ser rodado de novo: usa "if not exists" / "create or replace".
--
-- O que este passo cria:
--   parametros         limites configuráveis (minutos de atraso, dias de histórico)
--   veiculos_atual     retrato atual: uma linha por veículo (chave = placa do cavalo)
--   paradas_atual      paradas das viagens atuais (substituída a cada sincronização)
--   posicoes           histórico de posições (só entra quando a data da posição muda)
--   sincronizacao      registro de cada chamada ao Atlas (contagens e erro)
--   operadores         quem pode ver o painel (user_id do Supabase Auth)
--   aplicar_atlas()    grava a resposta do Atlas numa transação (só service_role)
--   registrar_falha_atlas()  registra falha de HTTP/JSON (só service_role)
--   limpar_historico() apaga posições com mais de N dias (agendada no passo 02)
--   v_painel           o que o painel lê, com a regra do ETA de destino
--
-- Nada aqui depende da conta ou do endereço do projeto: não há URL nem chave.
-- O CPF do motorista nunca é gravado (nem nas colunas, nem no "bruto").
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. Parâmetros (valores que a gestão pode trocar sem mudar código)
-- -----------------------------------------------------------------------------
create table if not exists public.parametros (
  chave     text primary key,
  valor     text not null,
  descricao text
);

insert into public.parametros (chave, valor, descricao) values
  ('minutos_posicao_atrasada', '30', 'Posição mais velha que isso aparece como desatualizada no painel'),
  ('minutos_sincronizacao_atrasada', '35', 'Sem sincronização boa há mais que isso: o "Atualizado às" fica vermelho'),
  ('dias_historico_posicoes', '15', 'Posições mais velhas que isso são apagadas pela limpeza diária'),
  ('dias_historico_sincronizacao', '90', 'Registros de sincronização mais velhos que isso são apagados')
on conflict (chave) do nothing;

-- Lê um parâmetro numérico; se faltar ou estiver inválido, usa o padrão.
create or replace function public.parametro_int(p_chave text, p_padrao integer)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (select case when btrim(valor) ~ '^\d+$' then btrim(valor)::integer end
       from public.parametros where chave = p_chave),
    p_padrao);
$$;


-- -----------------------------------------------------------------------------
-- 2. Conversores tolerantes (a API pode mudar formato de data/número)
-- -----------------------------------------------------------------------------

-- Data/hora: aceita ISO (com ou sem fuso), "dd/mm/aaaa hh:mm[:ss]", "dd/mm/aaaa"
-- e epoch em milissegundos. Sem fuso explícito = horário de America/Sao_Paulo.
-- Valor vazio, "-", "0" ou inválido (ex.: 31/02) vira null, sem erro.
create or replace function public.atlas_data(p_valor text)
returns timestamptz
language plpgsql
stable
set search_path = ''
as $$
declare
  v text := btrim(p_valor);
  m text[];
begin
  if v is null or v in ('', '-', '0', 'null', 'NULL') then
    return null;
  end if;

  -- dd/mm/aaaa [hh:mm[:ss]]
  m := regexp_match(v, '^(\d{1,2})/(\d{1,2})/(\d{4})(?:[ T]+(\d{1,2}):(\d{2})(?::(\d{2}(?:\.\d+)?))?)?$');
  if m is not null then
    return make_timestamptz(m[3]::int, m[2]::int, m[1]::int,
                            coalesce(m[4]::int, 0), coalesce(m[5]::int, 0),
                            coalesce(m[6]::double precision, 0), 'America/Sao_Paulo');
  end if;

  -- aaaa-mm-dd[Thh:mm[:ss[.fff]]][Z|+hh:mm|-hhmm]
  m := regexp_match(v, '^(\d{4})-(\d{2})-(\d{2})(?:[T ](\d{2}):(\d{2})(?::(\d{2}(?:\.\d+)?))?)?\s*(Z|[+-]\d{2}(?::?\d{2})?)?$', 'i');
  if m is not null then
    if m[7] is not null then
      return v::timestamptz;
    end if;
    return make_timestamptz(m[1]::int, m[2]::int, m[3]::int,
                            coalesce(m[4]::int, 0), coalesce(m[5]::int, 0),
                            coalesce(m[6]::double precision, 0), 'America/Sao_Paulo');
  end if;

  -- epoch em milissegundos
  if v ~ '^\d{12,13}$' then
    return to_timestamp(v::bigint / 1000.0);
  end if;

  return null;
exception when others then
  return null;
end;
$$;

-- Número: aceita 12.5, "12,5" e "1.234,5". Vazio ou inválido vira null.
create or replace function public.atlas_numero(p_valor text)
returns numeric
language plpgsql
immutable
set search_path = ''
as $$
declare
  v text := replace(btrim(p_valor), ' ', '');
begin
  if v is null or v = '' then
    return null;
  end if;
  if position(',' in v) > 0 and position('.' in v) > 0 then
    v := replace(replace(v, '.', ''), ',', '.');
  elsif position(',' in v) > 0 then
    v := replace(v, ',', '.');
  end if;
  if v ~ '^[+-]?\d+(\.\d+)?$' then
    return v::numeric;
  end if;
  return null;
end;
$$;

-- Texto: tira espaços das pontas; vazio vira null.
create or replace function public.atlas_texto(p_valor text)
returns text
language sql
immutable
set search_path = ''
as $$
  select nullif(btrim(p_valor), '');
$$;

-- SM: 0, vazio, "-" ou null = sem SM (devolve null).
create or replace function public.atlas_sm(p_valor text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
           when btrim(p_valor) is null or btrim(p_valor) in ('', '-', 'null', 'NULL') then null
           when btrim(p_valor) ~ '^0+([.,]0+)?$' then null
           else btrim(p_valor)
         end;
$$;

-- Placa: maiúscula, só letras e números (sem traço/espaço).
create or replace function public.atlas_placa(p_valor text)
returns text
language sql
immutable
set search_path = ''
as $$
  select nullif(regexp_replace(upper(coalesce(p_valor, '')), '[^A-Z0-9]', '', 'g'), '');
$$;

-- Lista: array fica como está; objeto vira [objeto]; o resto vira [].
create or replace function public.atlas_lista(p_valor jsonb)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select case jsonb_typeof(p_valor)
           when 'array' then p_valor
           when 'object' then jsonb_build_array(p_valor)
           else '[]'::jsonb
         end;
$$;

-- Remove o CPF de qualquer lugar do item: chaves com "cpf" no nome (em qualquer
-- nível) e textos no formato 000.000.000-00.
create or replace function public.atlas_sem_cpf(p_valor jsonb)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
begin
  case jsonb_typeof(p_valor)
    when 'object' then
      return coalesce(
        (select jsonb_object_agg(e.k, public.atlas_sem_cpf(e.v))
           from jsonb_each(p_valor) as e(k, v)
          where position('cpf' in lower(e.k)) = 0),
        '{}'::jsonb);
    when 'array' then
      return coalesce(
        (select jsonb_agg(public.atlas_sem_cpf(e.v) order by e.n)
           from jsonb_array_elements(p_valor) with ordinality as e(v, n)),
        '[]'::jsonb);
    when 'string' then
      if (p_valor #>> '{}') ~ '\d{3}\.\d{3}\.\d{3}-\d{2}' then
        return to_jsonb(regexp_replace(p_valor #>> '{}', '\d{3}\.\d{3}\.\d{3}-\d{2}', '***', 'g'));
      end if;
      return p_valor;
    else
      return p_valor;
  end case;
end;
$$;


-- -----------------------------------------------------------------------------
-- 3. Tabelas
-- -----------------------------------------------------------------------------

-- Retrato atual: uma linha por veículo.
-- placa = placa do cavalo normalizada; item sem placa e com SM = 'SEMPLACA:<sm>'.
create table if not exists public.veiculos_atual (
  placa                 text primary key,
  placa_carreta         text,
  frota_cavalo          text,
  vinculo_cavalo        text,
  vinculo_carreta       text,
  nome_cliente          text,
  operacao              text,
  codigo_sm             text,          -- null = sem SM (0, vazio, "-" ou null na API)
  status_sm             text,
  status_operacional    text,
  data_cadastro_sm      timestamptz,
  latitude              double precision,
  longitude             double precision,
  data_ultima_posicao   timestamptz,
  velocidade            numeric,
  macro_vigente         text,
  cidade_uf             text,
  localizacao_atual     text,
  motorista_nome        text,
  motorista_vinculo     text,
  rota_codigo           text,
  rota_descricao        text,
  rota_km_total         numeric,
  rota_tempo_total      text,
  origem_nome           text,
  origem_eta_original   timestamptz,
  origem_eta_real       timestamptz,
  origem_entrada        timestamptz,
  origem_saida          timestamptz,
  origem_entrada_real   timestamptz,
  origem_saida_real     timestamptz,
  destino_nome          text,
  destino_eta_original  timestamptz,
  destino_eta_real      timestamptz,
  destino_entrada       timestamptz,
  destino_saida         timestamptz,
  destino_entrada_real  timestamptz,
  destino_saida_real    timestamptz,
  previsao_inicio       timestamptz,
  previsao_fim          timestamptz,
  inicio_real           timestamptz,
  bruto                 jsonb not null,   -- item da API como veio, sem CPF
  visto_em              timestamptz not null default now(),
  ativo                 boolean not null default true,
  criado_em             timestamptz not null default now()
);

create index if not exists veiculos_atual_ativo_idx on public.veiculos_atual (ativo);

-- Paradas das viagens atuais (apagadas e regravadas a cada sincronização).
create table if not exists public.paradas_atual (
  id            bigint generated always as identity primary key,
  placa         text not null,
  codigo_sm     text,
  sequencia     integer,
  nome          text,
  eta_original  timestamptz,
  eta_real      timestamptz,
  entrada       timestamptz,
  saida         timestamptz,
  entrada_real  timestamptz,
  saida_real    timestamptz
);

create index if not exists paradas_atual_placa_idx on public.paradas_atual (placa, sequencia);

-- Histórico de posições. Sem coluna id de propósito: a chave é (placa, data_posicao),
-- o que já impede gravar a mesma posição duas vezes e economiza espaço.
create table if not exists public.posicoes (
  placa         text not null,
  latitude      double precision not null,
  longitude     double precision not null,
  velocidade    numeric,
  macro         text,
  data_posicao  timestamptz not null,
  inserido_em   timestamptz not null default now()
);

create unique index if not exists posicoes_placa_data_idx on public.posicoes (placa, data_posicao desc);
-- BRIN: índice minúsculo para a limpeza por data (as linhas entram em ordem de tempo).
create index if not exists posicoes_data_brin_idx on public.posicoes using brin (data_posicao);

-- Registro de cada sincronização.
create table if not exists public.sincronizacao (
  id            bigint generated always as identity primary key,
  fonte         text not null default 'atlas',
  iniciado_em   timestamptz not null default now(),
  terminado_em  timestamptz,
  http_status   integer,
  recebidos     integer,
  gravados      integer,
  sem_placa     integer,          -- itens sem placa E sem SM (ignorados)
  erro          text,             -- null = sincronização boa
  detalhes      jsonb             -- contagens extras (desativados, posições novas, etc.)
);

create index if not exists sincronizacao_terminado_idx on public.sincronizacao (terminado_em desc);

-- Quem pode ver o painel.
create table if not exists public.operadores (
  user_id    uuid primary key references auth.users (id) on delete cascade,
  nome       text not null,
  papel      text not null default 'operador' check (papel in ('operador', 'gestao')),
  ativo      boolean not null default true,
  criado_em  timestamptz not null default now()
);


-- -----------------------------------------------------------------------------
-- 4. Acesso: eh_operador()
-- -----------------------------------------------------------------------------
create or replace function public.eh_operador()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
      from public.operadores o
     where o.user_id = (select auth.uid())
       and o.ativo
  );
$$;


-- -----------------------------------------------------------------------------
-- 5. RPC aplicar_atlas: grava a resposta do Atlas numa transação só
-- -----------------------------------------------------------------------------
-- p_itens: o array (ou objeto único) devolvido pela API.
-- Trava: se vier vazio ou com menos de 50% dos veículos ativos hoje, NÃO altera
-- nada e só registra o erro em sincronizacao (como o script da planilha faz).
-- Linhas de exemplo (bruto com "_exemplo") não contam para a trava.
create or replace function public.aplicar_atlas(
  p_itens        jsonb,
  p_http_status  integer default 200,
  p_iniciado_em  timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_agora        timestamptz := now();
  v_itens        jsonb;
  v_recebidos    integer;
  v_validos      integer;
  v_ativos       integer;
  v_sem_placa    integer;
  v_sem_placa_sm integer;
  v_duplicados   integer;
  v_gravados     integer := 0;
  v_desativados  integer := 0;
  v_paradas      integer := 0;
  v_posicoes     integer := 0;
  v_dias         integer := public.parametro_int('dias_historico_posicoes', 15);
  v_erro         text;
  v_detalhes     jsonb;
begin
  -- Uma sincronização por vez.
  perform pg_advisory_xact_lock(hashtext('torre.aplicar_atlas'));

  -- Array, objeto único ou nada; só objetos; sem CPF em lugar nenhum.
  select coalesce(jsonb_agg(public.atlas_sem_cpf(e.item) order by e.n), '[]'::jsonb)
    into v_itens
    from jsonb_array_elements(public.atlas_lista(p_itens)) with ordinality as e(item, n)
   where jsonb_typeof(e.item) = 'object';

  v_recebidos := jsonb_array_length(v_itens);

  drop table if exists pg_temp._atlas;
  create temp table _atlas on commit drop as
  with base as (
    select e.n,
           e.item,
           public.atlas_lista(e.item -> 'placas')     as placas,
           public.atlas_lista(e.item -> 'motoristas') as motoristas,
           public.atlas_sm(e.item ->> 'codigo_sm')    as sm
      from jsonb_array_elements(v_itens) with ordinality as e(item, n)
  ),
  comp as (
    select b.*,
           -- cavalo = tipo CAVALO; se não houver, a primeira placa
           (select x.p from jsonb_array_elements(b.placas) with ordinality as x(p, i)
             order by coalesce(upper(btrim(x.p ->> 'tipo')) = 'CAVALO', false) desc, x.i
             limit 1) as cavalo,
           -- carreta = tipo CARRETA
           (select x.p from jsonb_array_elements(b.placas) with ordinality as x(p, i)
             where upper(btrim(x.p ->> 'tipo')) = 'CARRETA'
             order by x.i
             limit 1) as carreta,
           b.motoristas -> 0 as motorista
      from base b
  ),
  chaves as (
    select c.*,
           public.atlas_placa(coalesce(c.cavalo ->> 'placa', c.item ->> 'placa')) as placa_cavalo,
           public.atlas_numero(c.item ->> 'latitude')  as lat,
           public.atlas_numero(c.item ->> 'longitude') as lon
      from comp c
  )
  select k.n,
         coalesce(k.placa_cavalo, 'SEMPLACA:' || k.sm) as placa,
         k.placa_cavalo is not null                    as tem_placa,
         public.atlas_placa(k.carreta ->> 'placa')     as placa_carreta,
         public.atlas_texto(k.cavalo ->> 'frota')      as frota_cavalo,
         upper(public.atlas_texto(k.cavalo ->> 'vinculo'))  as vinculo_cavalo,
         upper(public.atlas_texto(k.carreta ->> 'vinculo')) as vinculo_carreta,
         public.atlas_texto(k.item ->> 'nome_cliente')       as nome_cliente,
         public.atlas_texto(k.item ->> 'operacao')           as operacao,
         k.sm                                                as codigo_sm,
         public.atlas_texto(k.item ->> 'status_sm')          as status_sm,
         public.atlas_texto(k.item ->> 'status_operacional') as status_operacional,
         public.atlas_data(k.item ->> 'data_cadastro_sm')    as data_cadastro_sm,
         -- 0,0 ou fora da faixa = sem posição
         case when k.lat between -90 and 90 and k.lon between -180 and 180
                   and not (k.lat = 0 and k.lon = 0)
              then k.lat::double precision end               as latitude,
         case when k.lat between -90 and 90 and k.lon between -180 and 180
                   and not (k.lat = 0 and k.lon = 0)
              then k.lon::double precision end               as longitude,
         public.atlas_data(k.item ->> 'data_ultima_posicao') as data_ultima_posicao,
         public.atlas_numero(k.item ->> 'velocidade')        as velocidade,
         public.atlas_texto(k.item ->> 'macro_vigente')      as macro_vigente,
         public.atlas_texto(k.item ->> 'cidade_uf')          as cidade_uf,
         public.atlas_texto(k.item ->> 'localizacao_atual')  as localizacao_atual,
         public.atlas_texto(k.motorista ->> 'nome')          as motorista_nome,
         upper(public.atlas_texto(k.motorista ->> 'vinculo')) as motorista_vinculo,
         public.atlas_texto(k.item -> 'rota' ->> 'codigo')    as rota_codigo,
         public.atlas_texto(k.item -> 'rota' ->> 'descricao') as rota_descricao,
         public.atlas_numero(k.item -> 'rota' ->> 'km_total') as rota_km_total,
         public.atlas_texto(k.item -> 'rota' ->> 'tempo_total') as rota_tempo_total,
         public.atlas_texto(k.item -> 'origem' ->> 'nome')          as origem_nome,
         public.atlas_data(k.item -> 'origem' ->> 'eta_original')   as origem_eta_original,
         public.atlas_data(k.item -> 'origem' ->> 'eta_real')       as origem_eta_real,
         public.atlas_data(k.item -> 'origem' ->> 'entrada')        as origem_entrada,
         public.atlas_data(k.item -> 'origem' ->> 'saida')          as origem_saida,
         public.atlas_data(k.item -> 'origem' ->> 'entrada_real')   as origem_entrada_real,
         public.atlas_data(k.item -> 'origem' ->> 'saida_real')     as origem_saida_real,
         public.atlas_texto(k.item -> 'destino' ->> 'nome')         as destino_nome,
         public.atlas_data(k.item -> 'destino' ->> 'eta_original')  as destino_eta_original,
         public.atlas_data(k.item -> 'destino' ->> 'eta_real')      as destino_eta_real,
         public.atlas_data(k.item -> 'destino' ->> 'entrada')       as destino_entrada,
         public.atlas_data(k.item -> 'destino' ->> 'saida')         as destino_saida,
         public.atlas_data(k.item -> 'destino' ->> 'entrada_real')  as destino_entrada_real,
         public.atlas_data(k.item -> 'destino' ->> 'saida_real')    as destino_saida_real,
         public.atlas_data(k.item ->> 'previsao_inicio') as previsao_inicio,
         public.atlas_data(k.item ->> 'previsao_fim')    as previsao_fim,
         public.atlas_data(k.item ->> 'inicio_real')     as inicio_real,
         public.atlas_lista(k.item -> 'paradas')         as paradas,
         k.item                                          as bruto
    from chaves k;

  -- Mesma placa repetida na resposta: fica a com SM válida e a posição mais nova.
  alter table pg_temp._atlas add column ordem integer;
  update pg_temp._atlas a
     set ordem = r.ordem
    from (select n, row_number() over (
                   partition by placa
                   order by (codigo_sm is not null) desc,
                            data_ultima_posicao desc nulls last,
                            data_cadastro_sm desc nulls last,
                            n desc) as ordem
            from pg_temp._atlas
           where placa is not null) r
   where a.n = r.n;

  select count(*) filter (where placa is null),
         count(*) filter (where not tem_placa and placa is not null),
         count(*) filter (where ordem > 1),
         count(*) filter (where ordem = 1)
    into v_sem_placa, v_sem_placa_sm, v_duplicados, v_validos
    from pg_temp._atlas;

  select count(*) into v_ativos
    from public.veiculos_atual
   where ativo and not (bruto ? '_exemplo');

  -- Trava dos 50%
  if v_validos = 0 then
    v_erro := format('trava: resposta sem veículos válidos (recebidos=%s, ativos hoje=%s); nada foi alterado',
                     v_recebidos, v_ativos);
  elsif v_validos * 2 < v_ativos then
    v_erro := format('trava: só %s veículos na resposta, menos de 50%% dos %s ativos hoje; nada foi alterado',
                     v_validos, v_ativos);
  end if;

  if v_erro is null then
    -- Retrato atual
    insert into public.veiculos_atual as va (
      placa, placa_carreta, frota_cavalo, vinculo_cavalo, vinculo_carreta,
      nome_cliente, operacao, codigo_sm, status_sm, status_operacional, data_cadastro_sm,
      latitude, longitude, data_ultima_posicao, velocidade, macro_vigente, cidade_uf, localizacao_atual,
      motorista_nome, motorista_vinculo,
      rota_codigo, rota_descricao, rota_km_total, rota_tempo_total,
      origem_nome, origem_eta_original, origem_eta_real, origem_entrada, origem_saida, origem_entrada_real, origem_saida_real,
      destino_nome, destino_eta_original, destino_eta_real, destino_entrada, destino_saida, destino_entrada_real, destino_saida_real,
      previsao_inicio, previsao_fim, inicio_real,
      bruto, visto_em, ativo)
    select placa, placa_carreta, frota_cavalo, vinculo_cavalo, vinculo_carreta,
           nome_cliente, operacao, codigo_sm, status_sm, status_operacional, data_cadastro_sm,
           latitude, longitude, data_ultima_posicao, velocidade, macro_vigente, cidade_uf, localizacao_atual,
           motorista_nome, motorista_vinculo,
           rota_codigo, rota_descricao, rota_km_total, rota_tempo_total,
           origem_nome, origem_eta_original, origem_eta_real, origem_entrada, origem_saida, origem_entrada_real, origem_saida_real,
           destino_nome, destino_eta_original, destino_eta_real, destino_entrada, destino_saida, destino_entrada_real, destino_saida_real,
           previsao_inicio, previsao_fim, inicio_real,
           bruto, v_agora, true
      from pg_temp._atlas
     where ordem = 1
    on conflict (placa) do update set
      placa_carreta = excluded.placa_carreta,
      frota_cavalo = excluded.frota_cavalo,
      vinculo_cavalo = excluded.vinculo_cavalo,
      vinculo_carreta = excluded.vinculo_carreta,
      nome_cliente = excluded.nome_cliente,
      operacao = excluded.operacao,
      codigo_sm = excluded.codigo_sm,
      status_sm = excluded.status_sm,
      status_operacional = excluded.status_operacional,
      data_cadastro_sm = excluded.data_cadastro_sm,
      latitude = excluded.latitude,
      longitude = excluded.longitude,
      data_ultima_posicao = excluded.data_ultima_posicao,
      velocidade = excluded.velocidade,
      macro_vigente = excluded.macro_vigente,
      cidade_uf = excluded.cidade_uf,
      localizacao_atual = excluded.localizacao_atual,
      motorista_nome = excluded.motorista_nome,
      motorista_vinculo = excluded.motorista_vinculo,
      rota_codigo = excluded.rota_codigo,
      rota_descricao = excluded.rota_descricao,
      rota_km_total = excluded.rota_km_total,
      rota_tempo_total = excluded.rota_tempo_total,
      origem_nome = excluded.origem_nome,
      origem_eta_original = excluded.origem_eta_original,
      origem_eta_real = excluded.origem_eta_real,
      origem_entrada = excluded.origem_entrada,
      origem_saida = excluded.origem_saida,
      origem_entrada_real = excluded.origem_entrada_real,
      origem_saida_real = excluded.origem_saida_real,
      destino_nome = excluded.destino_nome,
      destino_eta_original = excluded.destino_eta_original,
      destino_eta_real = excluded.destino_eta_real,
      destino_entrada = excluded.destino_entrada,
      destino_saida = excluded.destino_saida,
      destino_entrada_real = excluded.destino_entrada_real,
      destino_saida_real = excluded.destino_saida_real,
      previsao_inicio = excluded.previsao_inicio,
      previsao_fim = excluded.previsao_fim,
      inicio_real = excluded.inicio_real,
      bruto = excluded.bruto,
      visto_em = excluded.visto_em,
      ativo = true;
    get diagnostics v_gravados = row_count;

    -- Quem não veio fica inativo (não apaga).
    update public.veiculos_atual va
       set ativo = false
     where va.ativo
       and not exists (select 1 from pg_temp._atlas a where a.ordem = 1 and a.placa = va.placa);
    get diagnostics v_desativados = row_count;

    -- Paradas: substitui tudo.
    delete from public.paradas_atual where true;
    insert into public.paradas_atual (placa, codigo_sm, sequencia, nome,
                                      eta_original, eta_real, entrada, saida, entrada_real, saida_real)
    select a.placa,
           a.codigo_sm,
           coalesce(public.atlas_numero(p.v ->> 'sequencia')::integer, p.i::integer),
           public.atlas_texto(p.v ->> 'nome'),
           public.atlas_data(p.v ->> 'eta_original'),
           public.atlas_data(p.v ->> 'eta_real'),
           public.atlas_data(p.v ->> 'entrada'),
           public.atlas_data(p.v ->> 'saida'),
           public.atlas_data(p.v ->> 'entrada_real'),
           public.atlas_data(p.v ->> 'saida_real')
      from pg_temp._atlas a
     cross join lateral jsonb_array_elements(a.paradas) with ordinality as p(v, i)
     where a.ordem = 1
       and jsonb_typeof(p.v) = 'object';
    get diagnostics v_paradas = row_count;

    -- Histórico: só entra posição nova (mesma placa + mesma data_posicao = ignorada).
    insert into public.posicoes (placa, latitude, longitude, velocidade, macro, data_posicao)
    select a.placa, a.latitude, a.longitude, a.velocidade, a.macro_vigente, a.data_ultima_posicao
      from pg_temp._atlas a
     where a.ordem = 1
       and a.latitude is not null
       and a.longitude is not null
       and a.data_ultima_posicao is not null
       and a.data_ultima_posicao > v_agora - make_interval(days => v_dias)
    on conflict do nothing;
    get diagnostics v_posicoes = row_count;
  end if;

  v_detalhes := jsonb_build_object(
    'validos', v_validos,
    'ativos_antes', v_ativos,
    'sem_placa_com_sm', v_sem_placa_sm,
    'duplicados', v_duplicados,
    'desativados', v_desativados,
    'paradas', v_paradas,
    'posicoes_novas', v_posicoes);

  insert into public.sincronizacao (fonte, iniciado_em, terminado_em, http_status,
                                    recebidos, gravados, sem_placa, erro, detalhes)
  values ('atlas', coalesce(p_iniciado_em, v_agora), clock_timestamp(), p_http_status,
          v_recebidos, v_gravados, v_sem_placa, v_erro, v_detalhes);

  return jsonb_build_object(
    'ok', v_erro is null,
    'erro', v_erro,
    'recebidos', v_recebidos,
    'gravados', v_gravados,
    'sem_placa', v_sem_placa) || v_detalhes;
end;
$$;


-- -----------------------------------------------------------------------------
-- 6. RPC registrar_falha_atlas: HTTP diferente de 200, JSON inválido, timeout
-- -----------------------------------------------------------------------------
create or replace function public.registrar_falha_atlas(
  p_http_status  integer,
  p_erro         text,
  p_iniciado_em  timestamptz default null
)
returns bigint
language sql
security definer
set search_path = ''
as $$
  insert into public.sincronizacao (fonte, iniciado_em, terminado_em, http_status, recebidos, gravados, erro)
  values ('atlas', coalesce(p_iniciado_em, now()), clock_timestamp(), p_http_status, 0, 0,
          left(coalesce(nullif(btrim(p_erro), ''), 'falha sem descrição'), 500))
  returning id;
$$;


-- -----------------------------------------------------------------------------
-- 7. Limpeza diária (agendada no passo 02)
-- -----------------------------------------------------------------------------
create or replace function public.limpar_historico()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_posicoes integer;
  v_sinc     integer;
begin
  delete from public.posicoes
   where data_posicao < now() - make_interval(days => public.parametro_int('dias_historico_posicoes', 15));
  get diagnostics v_posicoes = row_count;

  delete from public.sincronizacao
   where iniciado_em < now() - make_interval(days => public.parametro_int('dias_historico_sincronizacao', 90));
  get diagnostics v_sinc = row_count;

  return jsonb_build_object('posicoes_apagadas', v_posicoes, 'sincronizacoes_apagadas', v_sinc);
end;
$$;


-- -----------------------------------------------------------------------------
-- 8. View do painel (security_invoker: respeita o RLS de quem consulta)
-- -----------------------------------------------------------------------------
-- Regra do ETA de destino (igual ao script da planilha):
--   tem placa e destino_eta_real          -> mostra o ETA
--   tem placa, sem ETA, com SM válida     -> 'Erro API Atlas'
--   tem placa, sem ETA, sem SM (vazio/0)  -> 'Sem SM'
create or replace view public.v_painel
with (security_invoker = true)
as
select v.placa,
       v.placa not like 'SEMPLACA:%'                       as tem_placa,
       v.placa_carreta,
       v.frota_cavalo,
       v.motorista_nome,
       coalesce(v.vinculo_cavalo, v.motorista_vinculo)     as vinculo,
       v.vinculo_cavalo,
       v.vinculo_carreta,
       v.motorista_vinculo,
       v.nome_cliente,
       v.operacao,
       v.codigo_sm,
       v.status_sm,
       v.status_operacional,
       v.macro_vigente,
       v.velocidade,
       v.latitude,
       v.longitude,
       v.cidade_uf,
       v.localizacao_atual,
       v.data_ultima_posicao,
       v.origem_nome,
       v.destino_nome,
       v.destino_eta_original,
       v.destino_eta_real,
       v.previsao_inicio,
       v.previsao_fim,
       v.inicio_real,
       v.rota_descricao,
       v.rota_km_total,
       case
         when v.placa like 'SEMPLACA:%' then null
         when v.destino_eta_real is not null then 'ok'
         when v.codigo_sm is not null then 'erro_api'
         else 'sem_sm'
       end                                                 as eta_situacao,
       case
         when v.destino_eta_real is not null
           then to_char(v.destino_eta_real at time zone 'America/Sao_Paulo', 'DD/MM/YYYY HH24:MI')
         when v.placa like 'SEMPLACA:%' then null
         when v.codigo_sm is not null then 'Erro API Atlas'
         else 'Sem SM'
       end                                                 as eta_destino_texto,
       (v.data_ultima_posicao is null
         or v.data_ultima_posicao < now() - make_interval(mins => cfg.minutos_atraso)) as posicao_atrasada,
       floor(extract(epoch from (now() - v.data_ultima_posicao)) / 60)::integer       as minutos_sem_posicao,
       coalesce(v.velocidade = 0, false)                   as parado,
       coalesce(v.velocidade > 0, false)                   as em_movimento,
       v.visto_em
  from public.veiculos_atual v
 cross join (select public.parametro_int('minutos_posicao_atrasada', 30) as minutos_atraso) cfg
 where v.ativo;


-- -----------------------------------------------------------------------------
-- 9. Permissões
-- -----------------------------------------------------------------------------
-- O Supabase dá, por padrão, acesso total às tabelas novas para anon e
-- authenticated. Aqui tiramos tudo e devolvemos só leitura para quem está logado;
-- o RLS ainda filtra: só operador ativo vê alguma linha.

revoke all on public.parametros, public.veiculos_atual, public.paradas_atual, public.posicoes,
              public.sincronizacao, public.operadores, public.v_painel
  from public, anon, authenticated;

grant select on public.parametros, public.veiculos_atual, public.paradas_atual, public.posicoes,
                public.sincronizacao, public.operadores, public.v_painel
  to authenticated;

grant all on public.parametros, public.veiculos_atual, public.paradas_atual, public.posicoes,
             public.sincronizacao, public.operadores, public.v_painel
  to service_role;

-- Funções: nenhuma fica aberta ao público.
revoke all on function public.parametro_int(text, integer)             from public, anon, authenticated;
revoke all on function public.atlas_data(text)                         from public, anon, authenticated;
revoke all on function public.atlas_numero(text)                       from public, anon, authenticated;
revoke all on function public.atlas_texto(text)                        from public, anon, authenticated;
revoke all on function public.atlas_sm(text)                           from public, anon, authenticated;
revoke all on function public.atlas_placa(text)                        from public, anon, authenticated;
revoke all on function public.atlas_lista(jsonb)                       from public, anon, authenticated;
revoke all on function public.atlas_sem_cpf(jsonb)                     from public, anon, authenticated;
revoke all on function public.aplicar_atlas(jsonb, integer, timestamptz)        from public, anon, authenticated;
revoke all on function public.registrar_falha_atlas(integer, text, timestamptz) from public, anon, authenticated;
revoke all on function public.limpar_historico()                       from public, anon, authenticated;
revoke all on function public.eh_operador()                            from public, anon, authenticated;

-- A view usa parametro_int() com as permissões de quem consulta.
grant execute on function public.parametro_int(text, integer) to authenticated, service_role;
grant execute on function public.eh_operador() to authenticated, service_role;
grant execute on function public.aplicar_atlas(jsonb, integer, timestamptz)        to service_role;
grant execute on function public.registrar_falha_atlas(integer, text, timestamptz) to service_role;
grant execute on function public.limpar_historico()                                to service_role;


-- -----------------------------------------------------------------------------
-- 10. RLS: leitura só para operador; nenhuma escrita pela API
-- -----------------------------------------------------------------------------
alter table public.parametros     enable row level security;
alter table public.veiculos_atual enable row level security;
alter table public.paradas_atual  enable row level security;
alter table public.posicoes       enable row level security;
alter table public.sincronizacao  enable row level security;
alter table public.operadores     enable row level security;

drop policy if exists parametros_ler_operador on public.parametros;
create policy parametros_ler_operador on public.parametros
  for select to authenticated using ((select public.eh_operador()));

drop policy if exists veiculos_ler_operador on public.veiculos_atual;
create policy veiculos_ler_operador on public.veiculos_atual
  for select to authenticated using ((select public.eh_operador()));

drop policy if exists paradas_ler_operador on public.paradas_atual;
create policy paradas_ler_operador on public.paradas_atual
  for select to authenticated using ((select public.eh_operador()));

drop policy if exists posicoes_ler_operador on public.posicoes;
create policy posicoes_ler_operador on public.posicoes
  for select to authenticated using ((select public.eh_operador()));

drop policy if exists sincronizacao_ler_operador on public.sincronizacao;
create policy sincronizacao_ler_operador on public.sincronizacao
  for select to authenticated using ((select public.eh_operador()));

-- Cada pessoa só enxerga a própria linha (o painel usa para saber nome/papel).
drop policy if exists operadores_ler_propria on public.operadores;
create policy operadores_ler_propria on public.operadores
  for select to authenticated using (user_id = (select auth.uid()));

-- Sem políticas de insert/update/delete: pela API ninguém grava.
-- Quem grava é a função aplicar_atlas (security definer), chamada só com o service role.
