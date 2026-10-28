// Testes da Edge Function sincronizar-atlas com fetch simulado.
// O Atlas é simulado; as RPCs do banco rodam de verdade no PGlite (passo 01).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { criarHandler, removerCpf } from '../supabase/functions/sincronizar-atlas/index.ts';
import { criarBanco, lerArquivo } from './apoio/banco.mjs';

const SUPABASE_URL = 'https://projeto-teste.invalid';
const ATLAS = 'https://externalnewconnect.atlasgr.com.br/travel/api/all-vehicles';
const SEGREDO = 'segredo-de-teste-123';

const ENV_PADRAO = {
  CRON_SECRET: SEGREDO,
  ATLAS_TOKEN: 'token-de-teste',
  ATLAS_CONTA: 'conta-de-teste',
  SUPABASE_URL,
  SUPABASE_SERVICE_ROLE_KEY: 'eyJ-chave-de-teste',
};

const amostra = JSON.parse(await lerArquivo('testes/amostra_atlas.json'));
const itemUnico = JSON.parse(await lerArquivo('testes/amostra_item_unico.json'));

// Um banco para o arquivo todo, limpo a cada teste.
const db = await criarBanco();

// Monta o ambiente: respostas do Atlas em sequência, RPCs no PGlite.
async function montar({ atlas, env = {}, rpcFalha = false } = {}) {
  await db.exec(`truncate public.veiculos_atual, public.paradas_atual, public.posicoes, public.sincronizacao`);
  const chamadas = { atlas: [], rpc: [] };
  const logs = [];
  const respostasAtlas = [...atlas];

  const fetchFalso = async (url, init = {}) => {
    if (url === ATLAS) {
      chamadas.atlas.push({ headers: init.headers });
      const r = respostasAtlas.shift();
      if (!r) throw new Error('chamada extra ao Atlas');
      if (r.demora) {
        await new Promise((res, rej) => {
          const t = setTimeout(res, r.demora);
          init.signal?.addEventListener('abort', () => {
            clearTimeout(t);
            rej(Object.assign(new Error('abortado'), { name: 'AbortError' }));
          });
        });
      }
      return new Response(r.corpo, { status: r.status });
    }
    const m = url.match(/^https:\/\/projeto-teste\.invalid\/rest\/v1\/rpc\/(\w+)$/);
    if (m) {
      const corpo = JSON.parse(init.body);
      chamadas.rpc.push({ nome: m[1], corpo, headers: init.headers, texto: init.body });
      if (rpcFalha && m[1] === 'aplicar_atlas') return new Response('{"message":"erro"}', { status: 500 });
      if (m[1] === 'aplicar_atlas') {
        const r = await db.query(`select public.aplicar_atlas($1::jsonb, $2, $3::timestamptz) as r`,
          [JSON.stringify(corpo.p_itens), corpo.p_http_status, corpo.p_iniciado_em]);
        return new Response(JSON.stringify(r.rows[0].r), { status: 200 });
      }
      if (m[1] === 'registrar_falha_atlas') {
        const r = await db.query(`select public.registrar_falha_atlas($1, $2, $3::timestamptz) as id`,
          [corpo.p_http_status, corpo.p_erro, corpo.p_iniciado_em]);
        return new Response(JSON.stringify(r.rows[0].id), { status: 200 });
      }
    }
    throw new Error('URL inesperada: ' + url);
  };

  const todasEnv = { ...ENV_PADRAO, ...env };
  const handler = criarHandler({
    env: (n) => todasEnv[n],
    fetch: fetchFalso,
    log: (d) => logs.push(JSON.stringify(d)),
    timeoutMs: 100,
    esperaEntreTentativasMs: 1,
  });
  const chamar = async (headers = { 'x-cron-secret': SEGREDO }, method = 'POST') => {
    const resp = await handler(new Request('http://local/sincronizar-atlas', { method, headers }));
    return { status: resp.status, corpo: await resp.json() };
  };
  const ultimaSinc = async () => (await db.query(`select * from public.sincronizacao order by id desc limit 1`)).rows[0];
  return { db, chamadas, logs, chamar, ultimaSinc };
}

const ok200 = (dados) => ({ status: 200, corpo: JSON.stringify(dados) });

test('sem o x-cron-secret certo: 401 e não chama o Atlas', async () => {
  const t = await montar({ atlas: [ok200(amostra)] });
  assert.equal((await t.chamar({})).status, 401);
  assert.equal((await t.chamar({ 'x-cron-secret': 'errado' })).status, 401);
  assert.equal((await t.chamar({ 'x-cron-secret': SEGREDO + 'x' })).status, 401);
  assert.equal((await t.chamar({ 'x-cron-secret': SEGREDO }, 'GET')).status, 405);
  assert.equal(t.chamadas.atlas.length, 0);
});

test('200 normal: grava a amostra, cabeçalhos certos e nenhum CPF chega à RPC', async () => {
  const t = await montar({ atlas: [ok200(amostra)] });
  const r = await t.chamar();
  assert.equal(r.status, 200, JSON.stringify(r.corpo));
  assert.equal(r.corpo.ok, true);
  assert.equal(r.corpo.recebidos, 30);
  assert.equal(r.corpo.gravados, 29);
  assert.equal(r.corpo.sem_placa, 1);
  assert.match(r.corpo.request_id, /^[0-9a-f-]{36}$/);

  const h = t.chamadas.atlas[0].headers;
  assert.equal(h.Authorization, 'Bearer token-de-teste');
  assert.equal(h['X-AJBORGES-AUTH'], 'conta-de-teste');
  assert.equal(h.Accept, 'application/json');

  const rpc = t.chamadas.rpc.find((c) => c.nome === 'aplicar_atlas');
  assert.equal(rpc.headers.apikey, 'eyJ-chave-de-teste');
  assert.equal(rpc.headers.Authorization, 'Bearer eyJ-chave-de-teste');
  assert.doesNotMatch(rpc.texto, /cpf/i, 'chave cpf chegou à RPC');
  assert.doesNotMatch(rpc.texto, /\d{3}\.\d{3}\.\d{3}-\d{2}/, 'número de CPF chegou à RPC');
  assert.equal(rpc.corpo.p_itens[0].motoristas[0].nome, 'Motorista Exemplo 01');

  // logs: só contagens/HTTP/request id; nada de nome ou CPF
  const logs = t.logs.join('\n');
  assert.doesNotMatch(logs, /Motorista|cpf|\d{3}\.\d{3}\.\d{3}-\d{2}|token-de-teste|conta-de-teste/i);
  assert.match(logs, /"recebidos":30/);

  const s = await t.ultimaSinc();
  assert.equal(s.http_status, 200);
  assert.equal(s.erro, null);
});

test('Atlas 401: registra a falha, não tenta de novo e não chama aplicar_atlas', async () => {
  const t = await montar({ atlas: [{ status: 401, corpo: '{"erro":"token inválido"}' }] });
  const r = await t.chamar();
  assert.equal(r.status, 502);
  assert.equal(r.corpo.http_atlas, 401);
  assert.equal(t.chamadas.atlas.length, 1);
  assert.deepEqual(t.chamadas.rpc.map((c) => c.nome), ['registrar_falha_atlas']);
  const s = await t.ultimaSinc();
  assert.equal(s.http_status, 401);
  assert.match(s.erro, /HTTP 401/);
});

test('JSON inválido: tenta 1 vez de novo, registra a falha e não chama aplicar_atlas', async () => {
  const t = await montar({ atlas: [{ status: 200, corpo: '<html>erro' }, { status: 200, corpo: '[{"placas": [' }] });
  const r = await t.chamar();
  assert.equal(r.status, 502);
  assert.equal(t.chamadas.atlas.length, 2);
  assert.deepEqual(t.chamadas.rpc.map((c) => c.nome), ['registrar_falha_atlas']);
  assert.match((await t.ultimaSinc()).erro, /JSON inválido/);
});

test('array vazio: chama aplicar_atlas e a trava não deixa apagar nada', async () => {
  const t = await montar({ atlas: [ok200(amostra), ok200([])] });
  assert.equal((await t.chamar()).status, 200);
  const r = await t.chamar();
  assert.equal(r.status, 409);
  assert.equal(r.corpo.ok, false);
  assert.match(r.corpo.erro, /^trava/);
  const ativos = (await t.db.query(`select count(*)::int as n from public.veiculos_atual where ativo`)).rows[0].n;
  assert.equal(ativos, 29);
});

test('HTTP 500 e depois 200: a nova tentativa resolve', async () => {
  const t = await montar({ atlas: [{ status: 500, corpo: 'erro' }, ok200(amostra)] });
  const r = await t.chamar();
  assert.equal(r.status, 200);
  assert.equal(t.chamadas.atlas.length, 2);
});

test('timeout: aborta a 1ª chamada e a 2ª resolve', async () => {
  const t = await montar({ atlas: [{ ...ok200(amostra), demora: 5000 }, ok200(amostra)] });
  const r = await t.chamar();
  assert.equal(r.status, 200);
  assert.equal(t.chamadas.atlas.length, 2);
});

test('timeout nas 2 tentativas: registra a falha', async () => {
  const t = await montar({ atlas: [{ ...ok200([]), demora: 5000 }, { ...ok200([]), demora: 5000 }] });
  const r = await t.chamar();
  assert.equal(r.status, 502);
  assert.match((await t.ultimaSinc()).erro, /não respondeu/);
});

test('item único em vez de array: vira lista de 1', async () => {
  const t = await montar({ atlas: [ok200(itemUnico)] });
  const r = await t.chamar();
  assert.equal(r.status, 200);
  assert.equal(r.corpo.recebidos, 1);
  const rpc = t.chamadas.rpc.find((c) => c.nome === 'aplicar_atlas');
  assert.ok(Array.isArray(rpc.corpo.p_itens));
  assert.doesNotMatch(rpc.texto, /cpf/i);
});

test('falha ao gravar no banco: 500 e registra a falha', async () => {
  const t = await montar({ atlas: [ok200(amostra)], rpcFalha: true });
  const r = await t.chamar();
  assert.equal(r.status, 500);
  assert.deepEqual(t.chamadas.rpc.map((c) => c.nome), ['aplicar_atlas', 'registrar_falha_atlas']);
});

test('chave nova (sb_secret_...) vai só no apikey', async () => {
  const t = await montar({ atlas: [ok200(itemUnico)], env: { SUPABASE_SERVICE_ROLE_KEY: 'sb_secret_teste' } });
  await t.chamar();
  const rpc = t.chamadas.rpc[0];
  assert.equal(rpc.headers.apikey, 'sb_secret_teste');
  assert.equal(rpc.headers.Authorization, undefined);
});

test('secrets faltando: 500 com os nomes (nunca os valores)', async () => {
  const t = await montar({ atlas: [ok200(amostra)], env: { ATLAS_TOKEN: '', ATLAS_CONTA: undefined } });
  const r = await t.chamar();
  assert.equal(r.status, 500);
  assert.match(r.corpo.erro, /ATLAS_TOKEN, ATLAS_CONTA/);
  assert.equal(t.chamadas.atlas.length, 0);

  const sem = await montar({ atlas: [], env: { CRON_SECRET: '' } });
  assert.equal((await sem.chamar({ 'x-cron-secret': '' })).status, 500);
});

test('removerCpf tira chaves com cpf em qualquer nível e mascara 000.000.000-00', () => {
  const r = removerCpf({
    motoristas: [{ nome: 'A', cpf: '1', CPF_Extra: '2' }],
    x: { y: { cpfMotorista: '3', obs: 'doc 000.000.001-00 e 000.000.002-00' } },
  });
  assert.deepEqual(r, { motoristas: [{ nome: 'A' }], x: { y: { obs: 'doc *** e ***' } } });
});
