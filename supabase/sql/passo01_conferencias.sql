-- =============================================================================
-- Torre de Controle Shopee - Conferências do passo 01
-- =============================================================================
-- Rode UM BLOCO POR VEZ (selecione do "begin;" até o "rollback;" e clique Run).
-- Cada bloco termina com um erro de propósito: "RESULTADO (nada foi salvo): ...".
-- Compare o texto com a linha "Esperado:" do bloco. O erro desfaz tudo; o
-- "rollback;" no final só fecha a transação. Nada fica gravado.
--
-- Rodar no SQL Editor do Supabase DO SITE, depois do passo 01.
--
-- Os usuários e veículos de teste são criados só dentro de cada bloco (placas
-- TSTE9xx, e-mails @exemplo.invalid). Se já houver dados reais, cada bloco marca
-- os veículos atuais como inativos SÓ dentro da transação, para a trava dos 50%
-- não atrapalhar; o rollback desfaz isso também.
--
-- Banco do site: os blocos só gravam no schema torre e em auth.users (usuários
-- de teste, desfeitos pelo erro final). Nas tabelas do public eles só LEEM
-- (bloco C15). O "admin do site" dos testes é só a claim
-- app_metadata.role = 'admin' no JWT simulado: nenhuma conta real é usada.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- [C1] Visitante sem login (anon) não lê nada
-- Esperado: veiculos_atual=bloqueado | paradas_atual=bloqueado | posicoes=bloqueado | sincronizacao=bloqueado | operadores=bloqueado | parametros=bloqueado | v_painel=bloqueado
-- -----------------------------------------------------------------------------
begin;
update torre.veiculos_atual set ativo = false where ativo;
select torre.aplicar_atlas(jsonb_build_array(
  jsonb_build_object('placas', jsonb_build_array(jsonb_build_object('placa', 'TSTE-901', 'tipo', 'CAVALO')),
                     'codigo_sm', '9900901', 'status_operacional', 'Em Viagem Carregado',
                     'latitude', -23.55, 'longitude', -46.63, 'velocidade', 60,
                     'data_ultima_posicao', now() - interval '5 minutes',
                     'paradas', jsonb_build_array(jsonb_build_object('nome', 'Parada teste', 'sequencia', 1)))));
select set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
set local role anon;
do $$
declare
  v_tabela text;
  v_qtd    bigint;
  v_saida  text[] := '{}';
begin
  foreach v_tabela in array array['veiculos_atual', 'paradas_atual', 'posicoes', 'sincronizacao',
                                  'operadores', 'parametros', 'v_painel'] loop
    begin
      execute format('select count(*) from torre.%I', v_tabela) into v_qtd;
      v_saida := v_saida || (v_tabela || '=' || v_qtd);
    exception when insufficient_privilege then
      v_saida := v_saida || (v_tabela || '=bloqueado');
    end;
  end loop;
  raise exception 'RESULTADO (nada foi salvo): %', array_to_string(v_saida, ' | ');
end $$;
rollback;


-- -----------------------------------------------------------------------------
-- [C2] Usuário logado que NÃO é operador não lê nada (nem a tabela operadores)
-- Esperado: veiculos_atual=0 | paradas_atual=0 | posicoes=0 | sincronizacao=0 | operadores=0 | parametros=0 | v_painel=0 | eh_operador=não
-- -----------------------------------------------------------------------------
begin;
update torre.veiculos_atual set ativo = false where ativo;
select torre.aplicar_atlas(jsonb_build_array(
  jsonb_build_object('placas', jsonb_build_array(jsonb_build_object('placa', 'TSTE-901', 'tipo', 'CAVALO')),
                     'codigo_sm', '9900901', 'status_operacional', 'Em Viagem Carregado',
                     'latitude', -23.55, 'longitude', -46.63, 'velocidade', 60,
                     'data_ultima_posicao', now() - interval '5 minutes',
                     'paradas', jsonb_build_array(jsonb_build_object('nome', 'Parada teste', 'sequencia', 1)))));
-- operador A (existe, mas não é quem consulta) e usuário B (logado, sem cadastro em operadores)
insert into auth.users (id, aud, role, email) values
  ('aaaaaaaa-0000-4000-8000-00000000000a', 'authenticated', 'authenticated', 'operador-a@exemplo.invalid'),
  ('aaaaaaaa-0000-4000-8000-00000000000b', 'authenticated', 'authenticated', 'usuario-b@exemplo.invalid');
insert into torre.operadores (user_id, nome, papel) values
  ('aaaaaaaa-0000-4000-8000-00000000000a', 'Operador Teste A', 'operador');
-- usuário B escolhido antes do set role
select set_config('request.jwt.claims',
         (select json_build_object('sub', id, 'role', 'authenticated')::text
            from auth.users where email = 'usuario-b@exemplo.invalid'), true);
set local role authenticated;
do $$
declare
  v_tabela text;
  v_qtd    bigint;
  v_saida  text[] := '{}';
begin
  foreach v_tabela in array array['veiculos_atual', 'paradas_atual', 'posicoes', 'sincronizacao',
                                  'operadores', 'parametros', 'v_painel'] loop
    begin
      execute format('select count(*) from torre.%I', v_tabela) into v_qtd;
      v_saida := v_saida || (v_tabela || '=' || v_qtd);
    exception when insufficient_privilege then
      v_saida := v_saida || (v_tabela || '=bloqueado');
    end;
  end loop;
  raise exception 'RESULTADO (nada foi salvo): % | eh_operador=%',
    array_to_string(v_saida, ' | '),
    case when torre.eh_operador() then 'sim' else 'não' end;
end $$;
rollback;


-- -----------------------------------------------------------------------------
-- [C3] Operador lê tudo, mas da tabela operadores só a própria linha
-- Esperado: veiculos=2 | paradas=2 | posicoes=2 | painel=2 | sincronizacao_le=sim | parametros_le=sim | operadores_visiveis=1 | eh_operador=sim
-- -----------------------------------------------------------------------------
begin;
update torre.veiculos_atual set ativo = false where ativo;
select torre.aplicar_atlas(jsonb_build_array(
  jsonb_build_object('placas', jsonb_build_array(jsonb_build_object('placa', 'TSTE-901', 'tipo', 'CAVALO')),
                     'codigo_sm', '9900901', 'status_operacional', 'Em Viagem Carregado',
                     'latitude', -23.55, 'longitude', -46.63, 'velocidade', 60,
                     'data_ultima_posicao', now() - interval '5 minutes',
                     'paradas', jsonb_build_array(jsonb_build_object('nome', 'Parada teste', 'sequencia', 1))),
  jsonb_build_object('placas', jsonb_build_array(jsonb_build_object('placa', 'TSTE-902', 'tipo', 'CAVALO')),
                     'codigo_sm', '9900902', 'status_operacional', 'Carregando',
                     'latitude', -22.90, 'longitude', -43.20, 'velocidade', 0,
                     'data_ultima_posicao', now() - interval '8 minutes',
                     'paradas', jsonb_build_array(jsonb_build_object('nome', 'Parada teste', 'sequencia', 1)))));
insert into auth.users (id, aud, role, email) values
  ('aaaaaaaa-0000-4000-8000-00000000000a', 'authenticated', 'authenticated', 'operador-a@exemplo.invalid'),
  ('aaaaaaaa-0000-4000-8000-00000000000c', 'authenticated', 'authenticated', 'operador-c@exemplo.invalid');
insert into torre.operadores (user_id, nome, papel) values
  ('aaaaaaaa-0000-4000-8000-00000000000a', 'Operador Teste A', 'operador'),
  ('aaaaaaaa-0000-4000-8000-00000000000c', 'Operador Teste C', 'gestao');
select set_config('request.jwt.claims',
         (select json_build_object('sub', id, 'role', 'authenticated')::text
            from auth.users where email = 'operador-a@exemplo.invalid'), true);
set local role authenticated;
do $$
begin
  raise exception 'RESULTADO (nada foi salvo): veiculos=% | paradas=% | posicoes=% | painel=% | sincronizacao_le=% | parametros_le=% | operadores_visiveis=% | eh_operador=%',
    (select count(*) from torre.veiculos_atual where placa like 'TSTE9%'),
    (select count(*) from torre.paradas_atual where placa like 'TSTE9%'),
    (select count(*) from torre.posicoes where placa like 'TSTE9%'),
    (select count(*) from torre.v_painel where placa like 'TSTE9%'),
    case when exists (select 1 from torre.sincronizacao) then 'sim' else 'NÃO' end,
    case when exists (select 1 from torre.parametros) then 'sim' else 'NÃO' end,
    (select count(*) from torre.operadores),
    case when torre.eh_operador() then 'sim' else 'não' end;
end $$;
rollback;


-- -----------------------------------------------------------------------------
-- [C4] Operador não grava nada pela API (nem se promove, nem chama as RPCs)
-- Esperado: insert_veiculos=bloqueado | update_veiculos=bloqueado | delete_posicoes=bloqueado | insert_sincronizacao=bloqueado | promover_se=bloqueado | cadastrar_outro=bloqueado | mudar_parametro=bloqueado | rpc_aplicar=bloqueado | rpc_falha=bloqueado | rpc_limpeza=bloqueado | papel_depois=operador | veiculos_depois=1
-- O 1º bloco tenta gravar como o operador e guarda os resultados (set_config, só
-- nesta transação); depois do reset role, o 2º bloco confere como dono do banco.
-- -----------------------------------------------------------------------------
begin;
update torre.veiculos_atual set ativo = false where ativo;
select torre.aplicar_atlas(jsonb_build_array(
  jsonb_build_object('placas', jsonb_build_array(jsonb_build_object('placa', 'TSTE-901', 'tipo', 'CAVALO')),
                     'codigo_sm', '9900901', 'status_operacional', 'Em Viagem Carregado',
                     'latitude', -23.55, 'longitude', -46.63, 'velocidade', 60,
                     'data_ultima_posicao', now() - interval '5 minutes')));
insert into auth.users (id, aud, role, email) values
  ('aaaaaaaa-0000-4000-8000-00000000000a', 'authenticated', 'authenticated', 'operador-a@exemplo.invalid');
insert into torre.operadores (user_id, nome, papel) values
  ('aaaaaaaa-0000-4000-8000-00000000000a', 'Operador Teste A', 'operador');
select set_config('request.jwt.claims',
         (select json_build_object('sub', id, 'role', 'authenticated')::text
            from auth.users where email = 'operador-a@exemplo.invalid'), true);
set local role authenticated;
do $$
declare
  v_saida text[] := '{}';
  v_teste text;
  v_sql   text;
begin
  for v_teste, v_sql in
    select * from (values
      ('insert_veiculos',      $s$insert into torre.veiculos_atual (placa, bruto) values ('TSTE999', '{}')$s$),
      ('update_veiculos',      $s$update torre.veiculos_atual set status_operacional = 'X' where placa = 'TSTE901'$s$),
      ('delete_posicoes',      $s$delete from torre.posicoes where placa = 'TSTE901'$s$),
      ('insert_sincronizacao', $s$insert into torre.sincronizacao (fonte) values ('atlas')$s$),
      ('promover_se',          $s$update torre.operadores set papel = 'gestao' where user_id = auth.uid()$s$),
      ('cadastrar_outro',      $s$insert into torre.operadores (user_id, nome) values (auth.uid(), 'x')$s$),
      ('mudar_parametro',      $s$update torre.parametros set valor = '999' where chave = 'minutos_posicao_atrasada'$s$),
      ('rpc_aplicar',          $s$select torre.aplicar_atlas('[]'::jsonb)$s$),
      ('rpc_falha',            $s$select torre.registrar_falha_atlas(500, 'x')$s$),
      ('rpc_limpeza',          $s$select torre.limpar_historico()$s$)
    ) t(a, b)
  loop
    begin
      execute v_sql;
      v_saida := v_saida || (v_teste || '=LIBERADO');
    exception when insufficient_privilege then
      v_saida := v_saida || (v_teste || '=bloqueado');
    end;
  end loop;
  perform set_config('c4.saida', array_to_string(v_saida, ' | '), true);
end $$;
reset role;
do $$
begin
  raise exception 'RESULTADO (nada foi salvo): % | papel_depois=% | veiculos_depois=%',
    current_setting('c4.saida'),
    (select papel from torre.operadores where user_id = 'aaaaaaaa-0000-4000-8000-00000000000a'),
    (select count(*) from torre.veiculos_atual where placa like 'TSTE9%' and status_operacional = 'Em Viagem Carregado');
end $$;
rollback;


-- -----------------------------------------------------------------------------
-- [C5] Visitante sem login (anon) também não grava nem chama as RPCs
-- Esperado: insert_veiculos=bloqueado | rpc_aplicar=bloqueado | rpc_falha=bloqueado | eh_operador=bloqueado
-- -----------------------------------------------------------------------------
begin;
select set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
set local role anon;
do $$
declare
  v_saida text[] := '{}';
  v_teste text;
  v_sql   text;
begin
  for v_teste, v_sql in
    select * from (values
      ('insert_veiculos', $s$insert into torre.veiculos_atual (placa, bruto) values ('TSTE999', '{}')$s$),
      ('rpc_aplicar',     $s$select torre.aplicar_atlas('[]'::jsonb)$s$),
      ('rpc_falha',       $s$select torre.registrar_falha_atlas(500, 'x')$s$),
      ('eh_operador',     $s$select torre.eh_operador()$s$)
    ) t(a, b)
  loop
    begin
      execute v_sql;
      v_saida := v_saida || (v_teste || '=LIBERADO');
    exception when insufficient_privilege then
      v_saida := v_saida || (v_teste || '=bloqueado');
    end;
  end loop;
  raise exception 'RESULTADO (nada foi salvo): %', array_to_string(v_saida, ' | ');
end $$;
rollback;


-- -----------------------------------------------------------------------------
-- [C6] Trava dos 50%: resposta vazia ou com menos da metade não altera nada
-- Esperado: com_1_de_4=bloqueou | ativos_apos_1=4 | erro_registrado=sim | vazio=bloqueou | ativos_apos_vazio=4 | com_2_de_4=aplicou | ativos_final=2
-- -----------------------------------------------------------------------------
begin;
update torre.veiculos_atual set ativo = false where ativo;
select torre.aplicar_atlas('[
  {"placas": [{"placa": "TSTE-911", "tipo": "CAVALO"}], "codigo_sm": "9900911"},
  {"placas": [{"placa": "TSTE-912", "tipo": "CAVALO"}], "codigo_sm": "9900912"},
  {"placas": [{"placa": "TSTE-913", "tipo": "CAVALO"}], "codigo_sm": "9900913"},
  {"placas": [{"placa": "TSTE-914", "tipo": "CAVALO"}], "codigo_sm": "9900914"}
]'::jsonb);
do $$
declare
  r1 jsonb;
  r2 jsonb;
  r3 jsonb;
  v_ativos_1 bigint;
  v_ativos_2 bigint;
  v_erro text;
begin
  r1 := torre.aplicar_atlas('[{"placas": [{"placa": "TSTE-911", "tipo": "CAVALO"}], "codigo_sm": "9900911"}]'::jsonb);
  select count(*) into v_ativos_1 from torre.veiculos_atual where ativo and placa like 'TSTE9%';
  select erro into v_erro from torre.sincronizacao order by id desc limit 1;
  r2 := torre.aplicar_atlas('[]'::jsonb);
  select count(*) into v_ativos_2 from torre.veiculos_atual where ativo and placa like 'TSTE9%';
  r3 := torre.aplicar_atlas('[
    {"placas": [{"placa": "TSTE-911", "tipo": "CAVALO"}], "codigo_sm": "9900911"},
    {"placas": [{"placa": "TSTE-912", "tipo": "CAVALO"}], "codigo_sm": "9900912"}]'::jsonb);
  raise exception 'RESULTADO (nada foi salvo): com_1_de_4=% | ativos_apos_1=% | erro_registrado=% | vazio=% | ativos_apos_vazio=% | com_2_de_4=% | ativos_final=%',
    case when (r1 ->> 'ok')::boolean then 'aplicou' else 'bloqueou' end,
    v_ativos_1,
    case when v_erro like 'trava:%' then 'sim' else 'NÃO' end,
    case when (r2 ->> 'ok')::boolean then 'aplicou' else 'bloqueou' end,
    v_ativos_2,
    case when (r3 ->> 'ok')::boolean then 'aplicou' else 'bloqueou' end,
    (select count(*) from torre.veiculos_atual where ativo and placa like 'TSTE9%');
end $$;
rollback;


-- -----------------------------------------------------------------------------
-- [C7] Histórico: a posição só entra quando a data da posição muda
-- Esperado: primeira=1 | repetida=1 | nova=2 | velha_fora=0 | sem_coordenada_fora=0
-- -----------------------------------------------------------------------------
begin;
update torre.veiculos_atual set ativo = false where ativo;
do $$
declare
  v_t1 timestamptz := now() - interval '20 minutes';
  v_t2 timestamptz := now() - interval '5 minutes';
  v_1 bigint;
  v_2 bigint;
  v_3 bigint;
begin
  -- TSTE921: posição recente; TSTE922: posição de 20 dias atrás; TSTE923: sem coordenada
  perform torre.aplicar_atlas(jsonb_build_array(
    jsonb_build_object('placas', jsonb_build_array(jsonb_build_object('placa', 'TSTE-921', 'tipo', 'CAVALO')),
                       'latitude', -23.55, 'longitude', -46.63, 'velocidade', 50, 'data_ultima_posicao', v_t1),
    jsonb_build_object('placas', jsonb_build_array(jsonb_build_object('placa', 'TSTE-922', 'tipo', 'CAVALO')),
                       'latitude', -23.55, 'longitude', -46.63, 'velocidade', 0, 'data_ultima_posicao', now() - interval '20 days'),
    jsonb_build_object('placas', jsonb_build_array(jsonb_build_object('placa', 'TSTE-923', 'tipo', 'CAVALO')),
                       'latitude', '', 'longitude', null, 'velocidade', 0, 'data_ultima_posicao', v_t1)));
  select count(*) into v_1 from torre.posicoes where placa = 'TSTE921';

  -- mesma data de posição de novo
  perform torre.aplicar_atlas(jsonb_build_array(
    jsonb_build_object('placas', jsonb_build_array(jsonb_build_object('placa', 'TSTE-921', 'tipo', 'CAVALO')),
                       'latitude', -23.55, 'longitude', -46.63, 'velocidade', 50, 'data_ultima_posicao', v_t1),
    jsonb_build_object('placas', jsonb_build_array(jsonb_build_object('placa', 'TSTE-922', 'tipo', 'CAVALO'))),
    jsonb_build_object('placas', jsonb_build_array(jsonb_build_object('placa', 'TSTE-923', 'tipo', 'CAVALO')))));
  select count(*) into v_2 from torre.posicoes where placa = 'TSTE921';

  -- data de posição nova
  perform torre.aplicar_atlas(jsonb_build_array(
    jsonb_build_object('placas', jsonb_build_array(jsonb_build_object('placa', 'TSTE-921', 'tipo', 'CAVALO')),
                       'latitude', -23.56, 'longitude', -46.64, 'velocidade', 55, 'data_ultima_posicao', v_t2),
    jsonb_build_object('placas', jsonb_build_array(jsonb_build_object('placa', 'TSTE-922', 'tipo', 'CAVALO'))),
    jsonb_build_object('placas', jsonb_build_array(jsonb_build_object('placa', 'TSTE-923', 'tipo', 'CAVALO')))));
  select count(*) into v_3 from torre.posicoes where placa = 'TSTE921';

  raise exception 'RESULTADO (nada foi salvo): primeira=% | repetida=% | nova=% | velha_fora=% | sem_coordenada_fora=%',
    v_1, v_2, v_3,
    (select count(*) from torre.posicoes where placa = 'TSTE922'),
    (select count(*) from torre.posicoes where placa = 'TSTE923');
end $$;
rollback;


-- -----------------------------------------------------------------------------
-- [C8] Regra do ETA de destino (3 casos) e datas nos dois formatos
-- Esperado: com_eta_br=28/10/2026 15:30 | com_eta_iso=29/10/2026 08:00 | sm_sem_eta=Erro API Atlas | sm_zero=Sem SM | sm_vazio=Sem SM | sm_traco=Sem SM | sem_placa=(vazio)
-- -----------------------------------------------------------------------------
begin;
update torre.veiculos_atual set ativo = false where ativo;
select torre.aplicar_atlas('[
  {"placas": [{"placa": "TSTE-931", "tipo": "CAVALO"}], "codigo_sm": "9900931", "destino": {"nome": "CD Teste", "eta_real": "28/10/2026 15:30"}},
  {"placas": [{"placa": "TSTE-932", "tipo": "CAVALO"}], "codigo_sm": 9900932, "destino": {"nome": "CD Teste", "eta_real": "2026-10-29T11:00:00Z"}},
  {"placas": [{"placa": "TSTE-933", "tipo": "CAVALO"}], "codigo_sm": "9900933", "destino": {"nome": "CD Teste", "eta_real": null}},
  {"placas": [{"placa": "TSTE-934", "tipo": "CAVALO"}], "codigo_sm": 0, "destino": {"nome": "CD Teste", "eta_real": ""}},
  {"placas": [{"placa": "TSTE-935", "tipo": "CAVALO"}], "codigo_sm": "", "destino": {}},
  {"placas": [{"placa": "TSTE-936", "tipo": "CAVALO"}], "codigo_sm": "-"},
  {"placas": [], "codigo_sm": "9900937"}
]'::jsonb);
do $$
begin
  raise exception 'RESULTADO (nada foi salvo): com_eta_br=% | com_eta_iso=% | sm_sem_eta=% | sm_zero=% | sm_vazio=% | sm_traco=% | sem_placa=%',
    (select eta_destino_texto from torre.v_painel where placa = 'TSTE931'),
    (select eta_destino_texto from torre.v_painel where placa = 'TSTE932'),
    (select eta_destino_texto from torre.v_painel where placa = 'TSTE933'),
    (select eta_destino_texto from torre.v_painel where placa = 'TSTE934'),
    (select eta_destino_texto from torre.v_painel where placa = 'TSTE935'),
    (select eta_destino_texto from torre.v_painel where placa = 'TSTE936'),
    coalesce((select eta_destino_texto from torre.v_painel where placa = 'SEMPLACA:9900937'), '(vazio)');
end $$;
rollback;


-- -----------------------------------------------------------------------------
-- [C9] Nenhum CPF fica gravado (nem nas colunas, nem dentro do bruto)
-- Esperado: veiculos=2 | motorista_gravado=sim | chave_cpf_no_bruto=0 | numero_cpf_no_banco=0 | cpf_no_log=0
-- -----------------------------------------------------------------------------
begin;
update torre.veiculos_atual set ativo = false where ativo;
select torre.aplicar_atlas('[
  {"placas": [{"placa": "TSTE-941", "tipo": "CAVALO"}], "codigo_sm": "9900941",
   "motoristas": [{"nome": "Motorista Teste Um", "cpf": "000.000.001-00", "vinculo": "FROTA"}],
   "extra": {"Motorista_CPF": "00000000100", "obs": "conferir doc 000.000.001-00"}},
  {"placas": [{"placa": "TSTE-942", "tipo": "CAVALO"}], "codigo_sm": "9900942",
   "motoristas": {"nome": "Motorista Teste Dois", "CPF": "00000000200", "vinculo": "AGREGADO"}}
]'::jsonb);
do $$
begin
  raise exception 'RESULTADO (nada foi salvo): veiculos=% | motorista_gravado=% | chave_cpf_no_bruto=% | numero_cpf_no_banco=% | cpf_no_log=%',
    (select count(*) from torre.veiculos_atual where placa like 'TSTE94%'),
    case when (select count(*) from torre.veiculos_atual
                where placa like 'TSTE94%' and motorista_nome like 'Motorista Teste%') = 2 then 'sim' else 'NÃO' end,
    (select count(*) from torre.veiculos_atual where bruto::text ilike '%cpf%'),
    (select count(*) from torre.veiculos_atual v
      where v::text like '%000.000.001-00%' or v::text like '%00000000100%' or v::text like '%00000000200%'),
    (select count(*) from torre.sincronizacao s where s::text ilike '%cpf%' or s::text like '%00000000100%');
end $$;
rollback;


-- -----------------------------------------------------------------------------
-- [C10] Item sem placa, placa repetida e objeto único (em vez de array)
-- Esperado: recebidos=5 | gravados=3 | sem_placa=1 | duplicados=1 | chave_sem_placa=SEMPLACA:9900952 | cavalo_sem_tipo=TSTE953 | carreta=TSTC951 | objeto_unico=1
-- -----------------------------------------------------------------------------
begin;
update torre.veiculos_atual set ativo = false where ativo;
do $$
declare
  r  jsonb;
  r2 jsonb;
begin
  r := torre.aplicar_atlas('[
    {"placas": [{"placa": "tstc-951", "tipo": "CARRETA"}, {"placa": "tste-951", "tipo": "CAVALO"}], "codigo_sm": "9900951"},
    {"placas": [{"placa": "TSTE 951", "tipo": "CAVALO"}], "codigo_sm": "0"},
    {"placas": [], "codigo_sm": "9900952"},
    {"placas": null, "codigo_sm": 0},
    {"placas": [{"placa": "TSTE-953"}], "codigo_sm": "9900953"}
  ]'::jsonb);
  r2 := torre.aplicar_atlas('{"placas": [{"placa": "TSTE-951", "tipo": "CAVALO"}], "codigo_sm": "9900951"}'::jsonb);
  raise exception 'RESULTADO (nada foi salvo): recebidos=% | gravados=% | sem_placa=% | duplicados=% | chave_sem_placa=% | cavalo_sem_tipo=% | carreta=% | objeto_unico=%',
    r ->> 'recebidos', r ->> 'gravados', r ->> 'sem_placa', r ->> 'duplicados',
    (select placa from torre.veiculos_atual where placa like 'SEMPLACA:99009%'),
    (select placa from torre.veiculos_atual where placa = 'TSTE953'),
    (select placa_carreta from torre.veiculos_atual where placa = 'TSTE951'),
    r2 ->> 'recebidos';
end $$;
rollback;


-- -----------------------------------------------------------------------------
-- [C11] Conversor de datas (horário de Brasília)
-- Esperado: br=2026-10-28 10:30 | br_segundos=2026-10-28 10:30:45 | br_so_data=2026-10-28 00:00 | iso_z=2026-10-28 10:30 | iso_sem_fuso=2026-10-28 10:30 | iso_com_fuso=2026-10-28 10:30 | invalida=null | traco=null | vazio=null
-- -----------------------------------------------------------------------------
begin;
do $$
declare
  f text := 'YYYY-MM-DD HH24:MI';
begin
  raise exception 'RESULTADO (nada foi salvo): br=% | br_segundos=% | br_so_data=% | iso_z=% | iso_sem_fuso=% | iso_com_fuso=% | invalida=% | traco=% | vazio=%',
    to_char(torre.atlas_data('28/10/2026 10:30') at time zone 'America/Sao_Paulo', f),
    to_char(torre.atlas_data('28/10/2026 10:30:45') at time zone 'America/Sao_Paulo', 'YYYY-MM-DD HH24:MI:SS'),
    to_char(torre.atlas_data('28/10/2026') at time zone 'America/Sao_Paulo', f),
    to_char(torre.atlas_data('2026-10-28T13:30:00Z') at time zone 'America/Sao_Paulo', f),
    to_char(torre.atlas_data('2026-10-28T10:30:00') at time zone 'America/Sao_Paulo', f),
    to_char(torre.atlas_data('2026-10-28T10:30:00.000-03:00') at time zone 'America/Sao_Paulo', f),
    coalesce(torre.atlas_data('31/02/2026 10:00')::text, 'null'),
    coalesce(torre.atlas_data('-')::text, 'null'),
    coalesce(torre.atlas_data('')::text, 'null');
end $$;
rollback;


-- -----------------------------------------------------------------------------
-- [C12] Admin do site (claim app_metadata.role) lê a Torre sem estar em torre.operadores
-- Esperado: veiculos=2 | paradas=2 | posicoes=2 | painel=2 | sincronizacao_le=sim | parametros_le=sim | operadores_visiveis=0 | admin_eh_operador=sim | diretoria_eh_operador=sim
-- -----------------------------------------------------------------------------
begin;
update torre.veiculos_atual set ativo = false where ativo;
select torre.aplicar_atlas(jsonb_build_array(
  jsonb_build_object('placas', jsonb_build_array(jsonb_build_object('placa', 'TSTE-901', 'tipo', 'CAVALO')),
                     'codigo_sm', '9900901', 'status_operacional', 'Em Viagem Carregado',
                     'latitude', -23.55, 'longitude', -46.63, 'velocidade', 60,
                     'data_ultima_posicao', now() - interval '5 minutes',
                     'paradas', jsonb_build_array(jsonb_build_object('nome', 'Parada teste', 'sequencia', 1))),
  jsonb_build_object('placas', jsonb_build_array(jsonb_build_object('placa', 'TSTE-902', 'tipo', 'CAVALO')),
                     'codigo_sm', '9900902', 'status_operacional', 'Carregando',
                     'latitude', -22.90, 'longitude', -43.20, 'velocidade', 0,
                     'data_ultima_posicao', now() - interval '8 minutes',
                     'paradas', jsonb_build_array(jsonb_build_object('nome', 'Parada teste', 'sequencia', 1)))));
insert into auth.users (id, aud, role, email) values
  ('aaaaaaaa-0000-4000-8000-00000000000d', 'authenticated', 'authenticated', 'admin-d@exemplo.invalid');
-- admin D escolhido antes do set role: claim de admin do site, nenhum registro em torre.operadores
select set_config('request.jwt.claims',
         (select json_build_object('sub', id, 'role', 'authenticated',
                                   'app_metadata', json_build_object('role', 'admin'))::text
            from auth.users where email = 'admin-d@exemplo.invalid'), true);
set local role authenticated;
do $$
declare
  v_admin     boolean := torre.eh_operador();
  v_diretoria boolean;
begin
  -- mesma sessão, agora com o papel "diretoria" (o outro papel que a public.is_admin() aceita)
  perform set_config('request.jwt.claims',
            jsonb_set(current_setting('request.jwt.claims')::jsonb, '{app_metadata,role}', '"diretoria"')::text, true);
  v_diretoria := torre.eh_operador();
  perform set_config('request.jwt.claims',
            jsonb_set(current_setting('request.jwt.claims')::jsonb, '{app_metadata,role}', '"admin"')::text, true);
  raise exception 'RESULTADO (nada foi salvo): veiculos=% | paradas=% | posicoes=% | painel=% | sincronizacao_le=% | parametros_le=% | operadores_visiveis=% | admin_eh_operador=% | diretoria_eh_operador=%',
    (select count(*) from torre.veiculos_atual where placa like 'TSTE9%'),
    (select count(*) from torre.paradas_atual where placa like 'TSTE9%'),
    (select count(*) from torre.posicoes where placa like 'TSTE9%'),
    (select count(*) from torre.v_painel where placa like 'TSTE9%'),
    case when exists (select 1 from torre.sincronizacao) then 'sim' else 'NÃO' end,
    case when exists (select 1 from torre.parametros) then 'sim' else 'NÃO' end,
    (select count(*) from torre.operadores),
    case when v_admin then 'sim' else 'não' end,
    case when v_diretoria then 'sim' else 'não' end;
end $$;
rollback;


-- -----------------------------------------------------------------------------
-- [C13] Motorista do site (logado, sem claim de admin, sem registro em torre.operadores) não lê nada
-- Esperado: veiculos_atual=0 | paradas_atual=0 | posicoes=0 | sincronizacao=0 | operadores=0 | parametros=0 | v_painel=0 | eh_operador=não
-- O motorista também tem "role": "admin" no user_metadata, que o próprio usuário
-- consegue editar: isso NÃO pode dar acesso (só vale o app_metadata).
-- -----------------------------------------------------------------------------
begin;
update torre.veiculos_atual set ativo = false where ativo;
select torre.aplicar_atlas(jsonb_build_array(
  jsonb_build_object('placas', jsonb_build_array(jsonb_build_object('placa', 'TSTE-901', 'tipo', 'CAVALO')),
                     'codigo_sm', '9900901', 'status_operacional', 'Em Viagem Carregado',
                     'latitude', -23.55, 'longitude', -46.63, 'velocidade', 60,
                     'data_ultima_posicao', now() - interval '5 minutes',
                     'paradas', jsonb_build_array(jsonb_build_object('nome', 'Parada teste', 'sequencia', 1)))));
insert into auth.users (id, aud, role, email) values
  ('aaaaaaaa-0000-4000-8000-00000000000a', 'authenticated', 'authenticated', 'operador-a@exemplo.invalid'),
  ('aaaaaaaa-0000-4000-8000-00000000000e', 'authenticated', 'authenticated', '00000000000@motorista.exemplo.invalid');
insert into torre.operadores (user_id, nome, papel) values
  ('aaaaaaaa-0000-4000-8000-00000000000a', 'Operador Teste A', 'operador');
-- motorista E escolhido antes do set role
select set_config('request.jwt.claims',
         (select json_build_object('sub', id, 'role', 'authenticated',
                                   'app_metadata', json_build_object('provider', 'email'),
                                   'user_metadata', json_build_object('role', 'admin', 'nome', 'Motorista Teste'))::text
            from auth.users where email = '00000000000@motorista.exemplo.invalid'), true);
set local role authenticated;
do $$
declare
  v_tabela text;
  v_qtd    bigint;
  v_saida  text[] := '{}';
begin
  foreach v_tabela in array array['veiculos_atual', 'paradas_atual', 'posicoes', 'sincronizacao',
                                  'operadores', 'parametros', 'v_painel'] loop
    begin
      execute format('select count(*) from torre.%I', v_tabela) into v_qtd;
      v_saida := v_saida || (v_tabela || '=' || v_qtd);
    exception when insufficient_privilege then
      v_saida := v_saida || (v_tabela || '=bloqueado');
    end;
  end loop;
  raise exception 'RESULTADO (nada foi salvo): % | eh_operador=%',
    array_to_string(v_saida, ' | '),
    case when torre.eh_operador() then 'sim' else 'não' end;
end $$;
rollback;


-- -----------------------------------------------------------------------------
-- [C14] Visitante sem login (anon) nem enxerga o schema torre
-- Esperado: usa_schema=não | tabelas_visiveis=0 | funcoes_visiveis=0 | ler_painel=bloqueado | chamar_eh_operador=bloqueado
-- -----------------------------------------------------------------------------
begin;
select set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
set local role anon;
do $$
declare
  v_painel   text;
  v_operador text;
begin
  begin
    perform count(*) from torre.v_painel;
    v_painel := 'LIBERADO';
  exception when insufficient_privilege then
    v_painel := 'bloqueado';
  end;
  begin
    perform torre.eh_operador();
    v_operador := 'LIBERADO';
  exception when insufficient_privilege then
    v_operador := 'bloqueado';
  end;
  raise exception 'RESULTADO (nada foi salvo): usa_schema=% | tabelas_visiveis=% | funcoes_visiveis=% | ler_painel=% | chamar_eh_operador=%',
    case when has_schema_privilege('torre', 'usage') then 'sim' else 'não' end,
    (select count(*) from information_schema.tables where table_schema = 'torre'),
    (select count(*) from information_schema.routines where routine_schema = 'torre'),
    v_painel,
    v_operador;
end $$;
rollback;


-- -----------------------------------------------------------------------------
-- [C15] Operador da Torre que NÃO é admin do site não ganha nada no public
-- Esperado: fichas_viagem=protegida | perfis=protegida | cadastros_agregados=protegida | eh_operador=sim
-- Só LEITURA no public. "protegida" = sem SELECT (has_table_privilege) OU com
-- SELECT mas a RLS do site devolve 0 linhas. Se aparecer "LÊ n LINHAS", quem
-- libera é uma regra do SITE (a Torre não dá grant nenhum no public): avise o
-- responsável pelo site antes de cadastrar operadores.
-- -----------------------------------------------------------------------------
begin;
insert into auth.users (id, aud, role, email) values
  ('aaaaaaaa-0000-4000-8000-00000000000f', 'authenticated', 'authenticated', 'operador-f@exemplo.invalid');
insert into torre.operadores (user_id, nome, papel) values
  ('aaaaaaaa-0000-4000-8000-00000000000f', 'Operador Teste F', 'operador');
-- operador F escolhido antes do set role (sem claim de admin)
select set_config('request.jwt.claims',
         (select json_build_object('sub', id, 'role', 'authenticated',
                                   'app_metadata', json_build_object('provider', 'email'))::text
            from auth.users where email = 'operador-f@exemplo.invalid'), true);
set local role authenticated;
do $$
declare
  v_tabela text;
  v_qtd    bigint;
  v_saida  text[] := '{}';
begin
  foreach v_tabela in array array['fichas_viagem', 'perfis', 'cadastros_agregados'] loop
    begin
      if to_regclass('public.' || v_tabela) is null then
        v_saida := v_saida || (v_tabela || '=NÃO EXISTE');
      elsif not has_table_privilege('public.' || v_tabela, 'select') then
        v_saida := v_saida || (v_tabela || '=protegida');
      else
        execute format('select count(*) from public.%I', v_tabela) into v_qtd;
        v_saida := v_saida || (v_tabela || case when v_qtd = 0 then '=protegida' else '=LÊ ' || v_qtd || ' LINHAS' end);
      end if;
    exception when insufficient_privilege then
      v_saida := v_saida || (v_tabela || '=protegida');
    end;
  end loop;
  raise exception 'RESULTADO (nada foi salvo): % | eh_operador=%',
    array_to_string(v_saida, ' | '),
    case when torre.eh_operador() then 'sim' else 'não' end;
end $$;
rollback;
