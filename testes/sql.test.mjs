// Testes do SQL no PGlite: passo 01, conferências, dados de exemplo, limpeza,
// passo 02 (com pg_cron, pg_net e Vault simulados), proteção do banco do site
// (nada fora do schema torre muda) e estimativa de tamanho.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readdir } from 'node:fs/promises';
import { criarBanco, blocosConferencia, rodarConferencia, lerArquivo, retratoForaDaTorre } from './apoio/banco.mjs';
import { montarDadosExemplo } from './gerar_dados_exemplo.mjs';

const um = async (db, sql, params) => (await db.query(sql, params)).rows[0];

// pg_cron, pg_net e Vault simulados (o PGlite não tem essas extensões), já com
// o job do site que a Torre não pode tocar.
const EXTENSOES_SIMULADAS = `
  create schema extensions;
  create schema vault;
  create table vault.decrypted_secrets (name text primary key, decrypted_secret text);
  insert into vault.decrypted_secrets values ('segredo_do_site', 'valor-do-site');
  create schema net;
  create table net.chamadas (url text, headers jsonb, body jsonb, timeout_milliseconds integer);
  create function net.http_post(url text, body jsonb default '{}', params jsonb default '{}',
                                headers jsonb default '{}', timeout_milliseconds integer default 5000)
    returns bigint language sql as $$
      insert into net.chamadas values (url, headers, body, timeout_milliseconds) returning 42::bigint $$;
  create schema cron;
  create table cron.job (jobid serial primary key, jobname text unique, schedule text, command text, active boolean default true);
  create function cron.schedule(job_name text, schedule text, command text) returns bigint language sql as $$
    insert into cron.job (jobname, schedule, command) values (job_name, schedule, command)
    on conflict (jobname) do update set schedule = excluded.schedule, command = excluded.command
    returning jobid::bigint $$;
  create function cron.unschedule(job_name text) returns boolean language sql as $$
    with d as (delete from cron.job where jobname = job_name returning 1) select exists (select 1 from d) $$;
  select cron.schedule('limpar-recusados-lgpd', '0 3 * * *', 'select 1 /* job do site */');`;

const lerPasso02 = async () => (await lerArquivo('supabase/sql/passo02_agendamento.sql'))
  .replace(/^create extension .*$/gm, '-- (extensão simulada no teste)');

test('passo 01 roda duas vezes seguidas sem erro', async () => {
  const db = await criarBanco();
  await db.exec(await lerArquivo('supabase/sql/passo01_atlas.sql'));
  const r = await um(db, `select count(*)::int as n from torre.parametros`);
  assert.equal(r.n, 4);
});

test('site protegido: nada fora do schema torre muda com todos os arquivos da Torre (nem com o drop schema torre)', async () => {
  const db = await criarBanco({ comPasso01: false });
  await db.exec(EXTENSOES_SIMULADAS);
  const antes = await retratoForaDaTorre(db);
  const jobsAntes = (await db.query(`select * from cron.job order by jobid`)).rows;
  const vaultAntes = (await db.query(`select * from vault.decrypted_secrets`)).rows;

  await db.exec(await lerArquivo('supabase/sql/passo01_atlas.sql'));
  await db.exec(await lerArquivo('supabase/sql/passo01_atlas.sql'));
  for (const b of blocosConferencia(await lerArquivo('supabase/sql/passo01_conferencias.sql'))) {
    const r = await rodarConferencia(db, b);
    assert.ok(r.resultado, `${b.id}: ${r.erro}`);
  }
  await db.exec(await lerArquivo('supabase/sql/dados_exemplo.sql'));
  await db.exec(await lerArquivo('supabase/sql/apagar_dados_exemplo.sql'));
  await db.exec(await lerPasso02());
  assert.deepEqual(await retratoForaDaTorre(db), antes);

  // o job e o segredo do site continuam iguais; os da Torre têm nomes próprios
  const jobs = (await db.query(`select * from cron.job order by jobid`)).rows;
  assert.deepEqual(jobs.filter((j) => !j.jobname.startsWith('torre-')), jobsAntes);
  assert.deepEqual((await db.query(`select * from vault.decrypted_secrets`)).rows, vaultAntes);

  // desfazer (README): unschedule dos jobs torre-... e drop schema torre cascade
  await db.exec(`select cron.unschedule('torre-sincronizar-atlas'); select cron.unschedule('torre-limpar-historico');
                 drop schema torre cascade;`);
  assert.deepEqual(await retratoForaDaTorre(db), antes);
  assert.deepEqual((await db.query(`select * from cron.job order by jobid`)).rows, jobsAntes);
});

test('arquivos SQL: "public." só aparece em public.is_admin() e na leitura do C15', async () => {
  const pasta = 'supabase/sql';
  const arquivos = (await readdir(new URL('../' + pasta, import.meta.url))).filter((a) => a.endsWith('.sql'));
  assert.ok(arquivos.length >= 5);
  for (const arquivo of arquivos) {
    const texto = await lerArquivo(`${pasta}/${arquivo}`);
    const c15 = arquivo === 'passo01_conferencias.sql' ? blocosConferencia(texto).find((b) => b.id === 'C15').sql : '';
    texto.split(/\r?\n/).forEach((linha, i) => {
      if (!/public\./i.test(linha)) return;
      const soIsAdmin = linha.replace(/public\.is_admin\(\)/g, '').match(/public\./i) === null;
      assert.ok(soIsAdmin || (c15 && c15.includes(linha)), `${arquivo}:${i + 1}: ${linha.trim()}`);
    });
  }
});

test('default privileges: tabela nova no torre não fica aberta para anon/authenticated', async () => {
  const db = await criarBanco();
  await db.exec(`create table torre.tabela_futura (id int); create sequence torre.sequencia_futura;`);
  const r = await um(db, `
    select has_table_privilege('anon', 'torre.tabela_futura', 'select') as anon_le,
           has_table_privilege('authenticated', 'torre.tabela_futura', 'select') as logado_le,
           has_table_privilege('authenticated', 'torre.tabela_futura', 'insert') as logado_grava,
           has_table_privilege('service_role', 'torre.tabela_futura', 'insert') as service_grava,
           has_sequence_privilege('authenticated', 'torre.sequencia_futura', 'usage') as logado_seq,
           has_schema_privilege('anon', 'torre', 'usage') as anon_schema,
           has_schema_privilege('authenticated', 'torre', 'usage') as logado_schema`);
  assert.deepEqual(r, { anon_le: false, logado_le: false, logado_grava: false, service_grava: true,
                        logado_seq: false, anon_schema: false, logado_schema: true });
  // nenhuma função do torre fica executável por anon/PUBLIC
  const f = await um(db, `
    select count(*) filter (where has_function_privilege('anon', p.oid, 'execute'))::int as anon,
           array_agg(p.proname order by p.proname) filter (where has_function_privilege('authenticated', p.oid, 'execute')) as logado
      from pg_proc p where p.pronamespace = 'torre'::regnamespace`);
  assert.equal(f.anon, 0);
  assert.deepEqual(f.logado, ['eh_operador', 'parametro_int']);
});

test('C15 acusa quando uma regra do site deixa o operador ler o public', async () => {
  const db = await criarBanco();
  await db.exec(`create policy perfis_aberta on public.perfis for select to authenticated using (true);`);
  const c15 = blocosConferencia(await lerArquivo('supabase/sql/passo01_conferencias.sql')).find((b) => b.id === 'C15');
  const r = await rodarConferencia(db, c15);
  assert.equal(r.resultado, 'fichas_viagem=protegida | perfis=LÊ 2 LINHAS | cadastros_agregados=protegida | eh_operador=sim');
});

test('acesso: admin/diretoria do site e operador ativo veem; motorista, operador inativo e user_metadata não', async () => {
  const db = await criarBanco();
  await db.exec(`insert into torre.operadores (user_id, nome, ativo) values
    ('cccccccc-0000-4000-8000-000000000001', 'Ativo', true), ('cccccccc-0000-4000-8000-000000000002', 'Inativo', false)`);
  const ver = async (claims) => {
    await db.exec(`begin; select set_config('request.jwt.claims', '${JSON.stringify(claims)}', true); set local role authenticated;`);
    try {
      return (await um(db, `select torre.eh_operador() as ok, (select count(*) from torre.parametros)::int as linhas`));
    } finally {
      await db.exec('rollback');
    }
  };
  const sub = 'cccccccc-0000-4000-8000-0000000000ff';
  assert.deepEqual(await ver({ sub, role: 'authenticated', app_metadata: { role: 'admin' } }), { ok: true, linhas: 4 });
  assert.deepEqual(await ver({ sub, role: 'authenticated', app_metadata: { role: 'diretoria' } }), { ok: true, linhas: 4 });
  assert.deepEqual(await ver({ sub: 'cccccccc-0000-4000-8000-000000000001', role: 'authenticated' }), { ok: true, linhas: 4 });
  assert.deepEqual(await ver({ sub: 'cccccccc-0000-4000-8000-000000000002', role: 'authenticated' }), { ok: false, linhas: 0 });
  assert.deepEqual(await ver({ sub, role: 'authenticated', app_metadata: { role: 'motorista' } }), { ok: false, linhas: 0 });
  assert.deepEqual(await ver({ sub, role: 'authenticated', user_metadata: { role: 'admin' } }), { ok: false, linhas: 0 });
  assert.deepEqual(await ver({ sub, role: 'authenticated' }), { ok: false, linhas: 0 });
});

test('conferências do passo 01 dão exatamente o "Esperado" de cada bloco', async (t) => {
  const db = await criarBanco();
  const blocos = blocosConferencia(await lerArquivo('supabase/sql/passo01_conferencias.sql'));
  assert.ok(blocos.length >= 15, 'blocos encontrados: ' + blocos.length);
  for (const b of blocos) {
    await t.test(`${b.id} ${b.titulo}`, async () => {
      const r = await rodarConferencia(db, b);
      assert.equal(r.resultado ?? r.erro, b.esperado);
    });
  }
  // as conferências não deixam nada gravado
  const r = await um(db, `select (select count(*) from torre.veiculos_atual)::int as v,
                                 (select count(*) from torre.sincronizacao)::int as s,
                                 (select count(*) from torre.operadores)::int as o`);
  assert.deepEqual(r, { v: 0, s: 0, o: 0 });
});

test('dados_exemplo.sql está em dia com testes/amostra_atlas.json', async () => {
  assert.equal(await lerArquivo('supabase/sql/dados_exemplo.sql'), montarDadosExemplo(),
    'rode: node testes/gerar_dados_exemplo.mjs');
});

test('dados de exemplo: carregam, cobrem todos os casos e não guardam CPF', async () => {
  const db = await criarBanco();
  await db.exec(await lerArquivo('supabase/sql/dados_exemplo.sql'));

  const s = await um(db, `select fonte, recebidos, gravados, sem_placa, erro, detalhes from torre.sincronizacao order by id desc limit 1`);
  assert.equal(s.fonte, 'exemplo');
  assert.equal(s.recebidos, 30);
  assert.equal(s.gravados, 29);
  assert.equal(s.sem_placa, 1);
  assert.equal(s.erro, null);
  assert.equal(s.detalhes.sem_placa_com_sm, 1);

  const p = await um(db, `
    select count(*)::int as total,
           count(*) filter (where eta_situacao = 'ok')::int as com_eta,
           count(*) filter (where eta_situacao = 'erro_api')::int as erro_api,
           count(*) filter (where eta_situacao = 'sem_sm')::int as sem_sm,
           count(*) filter (where posicao_atrasada)::int as atrasados,
           count(*) filter (where parado)::int as parados,
           count(*) filter (where em_movimento)::int as em_movimento,
           count(distinct vinculo)::int as vinculos,
           count(distinct status_operacional)::int as status,
           count(*) filter (where not tem_placa)::int as sem_placa,
           count(*) filter (where latitude is null)::int as sem_posicao
      from torre.v_painel`);
  assert.equal(p.total, 29);
  assert.equal(p.erro_api, 3);
  assert.equal(p.sem_sm, 5);
  assert.equal(p.com_eta, 20);
  assert.equal(p.atrasados, 4, '50 min, 3 h, 2 dias e o item sem posição');
  assert.equal(p.vinculos, 3);
  assert.equal(p.status, 5);
  assert.equal(p.sem_placa, 1);
  assert.equal(p.sem_posicao, 1);
  assert.ok(p.parados > 5 && p.em_movimento > 5, JSON.stringify(p));

  // latitude com vírgula ("-22,4705") foi convertida
  const v9 = await um(db, `select latitude, longitude from torre.veiculos_atual where placa = 'TSTE009'`);
  assert.deepEqual(v9, { latitude: -22.4705, longitude: -44.4509 });
  // placa sem tipo e minúscula vira cavalo normalizado
  assert.ok(await um(db, `select 1 as ok from torre.veiculos_atual where placa = 'TSTE006'`));
  // datas nos 4 formatos da amostra viraram timestamptz
  const d = await um(db, `select count(*) filter (where data_ultima_posicao is null)::int as sem_data from torre.veiculos_atual where placa like 'TSTE%'`);
  assert.equal(d.sem_data, 0);

  const cpf = await um(db, `
    select (select count(*) from torre.veiculos_atual v where v::text ilike '%cpf%' or v::text ~ '\\d{3}\\.\\d{3}\\.\\d{3}-\\d{2}')::int as veiculos,
           (select count(*) from torre.paradas_atual p where p::text ilike '%cpf%')::int as paradas,
           (select count(*) from torre.sincronizacao s where s::text ilike '%cpf%')::int as sinc`);
  assert.deepEqual(cpf, { veiculos: 0, paradas: 0, sinc: 0 });

  // sincronização "boa" recente e posições no histórico
  const h = await um(db, `select count(*)::int as n from torre.posicoes`);
  assert.equal(h.n, 28);
});

test('dados de exemplo não atrapalham a primeira sincronização real (trava ignora _exemplo)', async () => {
  const db = await criarBanco();
  await db.exec(await lerArquivo('supabase/sql/dados_exemplo.sql'));
  const r = await um(db, `select torre.aplicar_atlas($1::jsonb) as r`, [JSON.stringify([
    { placas: [{ placa: 'AAA1A11', tipo: 'CAVALO' }], codigo_sm: '1' },
    { placas: [{ placa: 'AAA1A12', tipo: 'CAVALO' }], codigo_sm: '2' },
  ])]);
  assert.equal(r.r.ok, true);
  const c = await um(db, `select count(*)::int as n from torre.v_painel`);
  assert.equal(c.n, 2, 'os veículos de exemplo ficam inativos');

  // e o dados_exemplo.sql se recusa a rodar com dados reais
  await assert.rejects(db.exec(await lerArquivo('supabase/sql/dados_exemplo.sql')), /dados reais/);
  await db.exec('rollback').catch(() => {});

  await db.exec(await lerArquivo('supabase/sql/apagar_dados_exemplo.sql'));
  const z = await um(db, `select (select count(*) from torre.veiculos_atual where bruto ? '_exemplo')::int as v,
                                 (select count(*) from torre.veiculos_atual)::int as todos,
                                 (select count(*) from torre.sincronizacao where fonte = 'exemplo')::int as s`);
  assert.deepEqual(z, { v: 0, todos: 2, s: 0 });
});

test('item único (objeto em vez de array) é aceito', async () => {
  const db = await criarBanco();
  const r = await um(db, `select torre.aplicar_atlas($1::jsonb) as r`, [await lerArquivo('testes/amostra_item_unico.json')]);
  assert.equal(r.r.ok, true);
  assert.equal(r.r.recebidos, 1);
  const v = await um(db, `select placa, motorista_nome, bruto::text ilike '%cpf%' as tem_cpf from torre.veiculos_atual`);
  assert.deepEqual(v, { placa: 'TSTE031', motorista_nome: 'Motorista Exemplo 31', tem_cpf: false });
});

test('limpar_historico apaga só posições com mais de 15 dias', async () => {
  const db = await criarBanco();
  await db.exec(`
    insert into torre.posicoes (placa, latitude, longitude, data_posicao) values
      ('TSTE001', -23, -46, now() - interval '16 days'),
      ('TSTE001', -23, -46, now() - interval '14 days'),
      ('TSTE001', -23, -46, now() - interval '1 hour');
    insert into torre.sincronizacao (iniciado_em) values (now() - interval '100 days'), (now());`);
  const r = await um(db, `select torre.limpar_historico() as r`);
  assert.deepEqual(r.r, { posicoes_apagadas: 1, sincronizacoes_apagadas: 1 });
});

test('passo 02: disparo lê URL e segredo do Vault e agenda os 2 jobs (sem tocar no job do site)', async () => {
  const db = await criarBanco();
  await db.exec(EXTENSOES_SIMULADAS);
  const passo02 = await lerPasso02();
  assert.doesNotMatch(passo02, /https?:\/\/[^<\s]*supabase\.co/, 'sem URL fixa no SQL');
  assert.match(await lerArquivo('supabase/sql/passo02_agendamento.sql'), /^create extension if not exists pg_cron/m);
  assert.doesNotMatch(await lerArquivo('supabase/sql/passo02_agendamento.sql'), /^\s*drop /im, 'nenhum drop');
  await db.exec(passo02);
  await db.exec(passo02); // rodar de novo só atualiza

  const jobs = (await db.query(`select jobname, schedule, command from cron.job order by jobname`)).rows;
  assert.deepEqual(jobs.map((j) => [j.jobname, j.schedule, j.command]), [
    ['limpar-recusados-lgpd', '0 3 * * *', 'select 1 /* job do site */'],
    ['torre-limpar-historico', '17 6 * * *', 'select torre.limpar_historico()'],
    ['torre-sincronizar-atlas', '*/15 * * * *', 'select torre.disparar_sincronizacao_atlas()'],
  ]);

  await assert.rejects(db.query(`select torre.disparar_sincronizacao_atlas()`), /Vault incompleto/);

  await db.exec(`insert into vault.decrypted_secrets values
    ('torre_url_sincronizar_atlas', 'https://projeto-teste.invalid/functions/v1/sincronizar-atlas'),
    ('torre_cron_secret', 'segredo-de-teste')`);
  const r = await um(db, `select torre.disparar_sincronizacao_atlas() as id`);
  assert.equal(Number(r.id), 42);
  const c = await um(db, `select * from net.chamadas`);
  assert.equal(c.url, 'https://projeto-teste.invalid/functions/v1/sincronizar-atlas');
  assert.equal(c.headers['x-cron-secret'], 'segredo-de-teste');
  assert.equal(c.timeout_milliseconds, 60000);

  // ninguém pela API consegue disparar
  await db.exec(`begin; set local role authenticated;`);
  await assert.rejects(db.query(`select torre.disparar_sincronizacao_atlas()`), /permission denied/);
  await db.exec(`rollback`);
});

test('estimativa de tamanho do histórico de posições', async () => {
  const db = await criarBanco();
  // 100 veículos, 1 posição nova a cada 15 min (96/dia), 15 dias de retenção
  await db.exec(`
    insert into torre.posicoes (placa, latitude, longitude, velocidade, macro, data_posicao)
    select 'TSTE' || lpad(v::text, 3, '0'),
           -23 + random(), -46 + random(), (random() * 90)::int, 'INICIO DE VIAGEM',
           now() - make_interval(mins => 15 * p)
      from generate_series(1, 100) v, generate_series(0, 96 * 15 - 1) p;
    analyze torre.posicoes;`);
  const r = await um(db, `select count(*)::int as linhas,
                                 pg_total_relation_size('torre.posicoes')::bigint as bytes
                            from torre.posicoes`);
  const porLinha = Number(r.bytes) / r.linhas;
  const mbMes100 = (porLinha * 100 * 96 * 30) / 1024 / 1024;
  console.log(`[tamanho] ${r.linhas} linhas = ${(Number(r.bytes) / 1024 / 1024).toFixed(1)} MB ` +
              `(${porLinha.toFixed(0)} bytes/linha com índices). ` +
              `100 veículos: ~${mbMes100.toFixed(0)} MB por mês sem limpeza; ` +
              `com 15 dias de retenção, ~${(mbMes100 / 2).toFixed(0)} MB fixos.`);
  assert.ok(porLinha < 250, `bytes por linha: ${porLinha}`);
});
