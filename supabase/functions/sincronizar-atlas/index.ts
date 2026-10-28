// =============================================================================
// Torre de Controle Shopee - Edge Function "sincronizar-atlas"
// =============================================================================
// Chamada pelo pg_cron (passo 02) a cada 15 min. Busca todos os veículos ativos
// na API do Atlas, tira o CPF e entrega para a RPC aplicar_atlas (passo 01).
//
// Secrets (Edge Functions > Secrets; nenhum valor fica no código):
//   ATLAS_TOKEN   token do Atlas (vai no "Authorization: Bearer ...")
//   ATLAS_CONTA   valor do cabeçalho X-AJBORGES-AUTH
//   CRON_SECRET   segredo que o agendamento manda no cabeçalho x-cron-secret
// Variáveis padrão do Supabase (já existem em toda função):
//   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
// Opcional: ATLAS_URL (troca o endereço da API sem mexer no código).
//
// Publicar com "Verify JWT" DESLIGADO: quem protege é o x-cron-secret.
// Logs: só contagens, status HTTP e request id. Nunca nome ou CPF.
// =============================================================================

const ATLAS_URL_PADRAO = 'https://externalnewconnect.atlasgr.com.br/travel/api/all-vehicles';
const TIMEOUT_MS = 25_000;
const TENTATIVAS = 2; // 1 chamada + 1 nova tentativa

type Dependencias = {
  env: (nome: string) => string | undefined;
  fetch: typeof fetch;
  log?: (dados: Record<string, unknown>) => void;
  timeoutMs?: number;
  esperaEntreTentativasMs?: number;
};

type ResultadoAtlas =
  | { ok: true; status: number; itens: unknown[] }
  | { ok: false; status: number | null; erro: string };

// ---------------------------------------------------------------------------
// Utilitários
// ---------------------------------------------------------------------------

function json(corpo: unknown, status = 200): Response {
  return new Response(JSON.stringify(corpo), {
    status,
    headers: { 'Content-Type': 'application/json; charset=utf-8' },
  });
}

// Compara em tempo constante: compara os SHA-256 dos dois valores, assim nem o
// tamanho do segredo vaza pelo tempo de resposta.
async function segredoConfere(recebido: string, esperado: string): Promise<boolean> {
  const cod = new TextEncoder();
  const [a, b] = await Promise.all([
    crypto.subtle.digest('SHA-256', cod.encode(recebido)),
    crypto.subtle.digest('SHA-256', cod.encode(esperado)),
  ]);
  const va = new Uint8Array(a);
  const vb = new Uint8Array(b);
  let diferenca = 0;
  for (let i = 0; i < va.length; i++) diferenca |= va[i] ^ vb[i];
  return diferenca === 0;
}

const TEM_CPF = /\d{3}\.\d{3}\.\d{3}-\d{2}/;
const TODOS_CPF = /\d{3}\.\d{3}\.\d{3}-\d{2}/g;

// Tira o CPF de qualquer lugar: chaves com "cpf" no nome (em qualquer nível,
// inclusive motoristas[].cpf) e textos no formato 000.000.000-00.
export function removerCpf(valor: unknown): unknown {
  if (Array.isArray(valor)) return valor.map(removerCpf);
  if (valor && typeof valor === 'object') {
    const limpo: Record<string, unknown> = {};
    for (const [chave, v] of Object.entries(valor as Record<string, unknown>)) {
      if (chave.toLowerCase().includes('cpf')) continue;
      limpo[chave] = removerCpf(v);
    }
    return limpo;
  }
  if (typeof valor === 'string' && TEM_CPF.test(valor)) return valor.replace(TODOS_CPF, '***');
  return valor;
}

// A API devolve um array ou, às vezes, um objeto único.
export function normalizarResposta(dados: unknown): unknown[] {
  if (Array.isArray(dados)) return dados.filter((i) => i && typeof i === 'object' && !Array.isArray(i));
  if (dados && typeof dados === 'object') return [dados];
  return [];
}

function esperar(ms: number): Promise<void> {
  return new Promise((r) => setTimeout(r, ms));
}

// ---------------------------------------------------------------------------
// Atlas
// ---------------------------------------------------------------------------

async function buscarAtlas(deps: Dependencias, url: string, token: string, conta: string): Promise<ResultadoAtlas> {
  const timeoutMs = deps.timeoutMs ?? TIMEOUT_MS;
  let ultimo: ResultadoAtlas = { ok: false, status: null, erro: 'sem tentativa' };

  for (let tentativa = 1; tentativa <= TENTATIVAS; tentativa++) {
    if (tentativa > 1) await esperar(deps.esperaEntreTentativasMs ?? 2000);

    const controle = new AbortController();
    const relogio = setTimeout(() => controle.abort(), timeoutMs);
    try {
      const resp = await deps.fetch(url, {
        method: 'GET',
        headers: {
          Authorization: `Bearer ${token}`,
          'X-AJBORGES-AUTH': conta,
          Accept: 'application/json',
        },
        signal: controle.signal,
      });
      const texto = await resp.text();

      if (resp.status !== 200) {
        ultimo = { ok: false, status: resp.status, erro: `Atlas respondeu HTTP ${resp.status}` };
        // 4xx (token/conta errados) não melhora tentando de novo; 429 e 5xx, sim.
        if (resp.status >= 400 && resp.status < 500 && resp.status !== 429) return ultimo;
        continue;
      }

      try {
        return { ok: true, status: 200, itens: normalizarResposta(JSON.parse(texto)) };
      } catch {
        ultimo = { ok: false, status: 200, erro: 'Atlas respondeu HTTP 200 com JSON inválido' };
        continue;
      }
    } catch (e) {
      const abortou = e instanceof Error && e.name === 'AbortError';
      ultimo = {
        ok: false,
        status: null,
        erro: abortou ? `Atlas não respondeu em ${Math.round(timeoutMs / 1000)} s` : 'falha de rede ao chamar o Atlas',
      };
    } finally {
      clearTimeout(relogio);
    }
  }
  return ultimo;
}

// ---------------------------------------------------------------------------
// Banco (RPCs via REST, com o service role)
// ---------------------------------------------------------------------------

async function chamarRpc(deps: Dependencias, nome: string, corpo: unknown): Promise<{ status: number; dados: unknown }> {
  const base = (deps.env('SUPABASE_URL') ?? '').replace(/\/+$/, '');
  const chave = deps.env('SUPABASE_SERVICE_ROLE_KEY') ?? '';
  const headers: Record<string, string> = {
    apikey: chave,
    'Content-Type': 'application/json',
    Accept: 'application/json',
  };
  // Chave antiga (JWT) também vai no Authorization; a nova (sb_secret_...) só no apikey.
  if (chave.startsWith('eyJ')) headers.Authorization = `Bearer ${chave}`;

  const resp = await deps.fetch(`${base}/rest/v1/rpc/${nome}`, {
    method: 'POST',
    headers,
    body: JSON.stringify(corpo),
  });
  const texto = await resp.text();
  let dados: unknown = null;
  try {
    dados = texto ? JSON.parse(texto) : null;
  } catch {
    dados = null;
  }
  return { status: resp.status, dados };
}

// ---------------------------------------------------------------------------
// Handler
// ---------------------------------------------------------------------------

export function criarHandler(deps: Dependencias) {
  const log = deps.log ?? ((dados) => console.log(JSON.stringify(dados)));

  return async function handler(req: Request): Promise<Response> {
    const requestId = crypto.randomUUID();
    const iniciadoEm = new Date().toISOString();

    if (req.method !== 'POST') {
      return json({ ok: false, erro: 'use POST', request_id: requestId }, 405);
    }

    const segredo = deps.env('CRON_SECRET') ?? '';
    if (!segredo) {
      log({ request_id: requestId, etapa: 'config', erro: 'CRON_SECRET não configurado' });
      return json({ ok: false, erro: 'função sem configuração', request_id: requestId }, 500);
    }
    if (!(await segredoConfere(req.headers.get('x-cron-secret') ?? '', segredo))) {
      log({ request_id: requestId, etapa: 'auth', http: 401 });
      return json({ ok: false, erro: 'não autorizado', request_id: requestId }, 401);
    }

    const token = deps.env('ATLAS_TOKEN') ?? '';
    const conta = deps.env('ATLAS_CONTA') ?? '';
    const faltando = [
      ['ATLAS_TOKEN', token],
      ['ATLAS_CONTA', conta],
      ['SUPABASE_URL', deps.env('SUPABASE_URL')],
      ['SUPABASE_SERVICE_ROLE_KEY', deps.env('SUPABASE_SERVICE_ROLE_KEY')],
    ].filter(([, v]) => !v).map(([n]) => n);
    if (faltando.length) {
      log({ request_id: requestId, etapa: 'config', faltando });
      return json({ ok: false, erro: `faltam secrets: ${faltando.join(', ')}`, request_id: requestId }, 500);
    }

    const url = deps.env('ATLAS_URL') || ATLAS_URL_PADRAO;
    const atlas = await buscarAtlas(deps, url, token, conta);

    if (!atlas.ok) {
      log({ request_id: requestId, etapa: 'atlas', http: atlas.status, erro: atlas.erro });
      const falha = await chamarRpc(deps, 'registrar_falha_atlas', {
        p_http_status: atlas.status,
        p_erro: atlas.erro,
        p_iniciado_em: iniciadoEm,
      }).catch(() => ({ status: 0, dados: null }));
      if (falha.status !== 200) log({ request_id: requestId, etapa: 'registrar_falha', http: falha.status });
      return json({ ok: false, etapa: 'atlas', http_atlas: atlas.status, erro: atlas.erro, request_id: requestId }, 502);
    }

    const itens = atlas.itens.map(removerCpf);
    log({ request_id: requestId, etapa: 'atlas', http: atlas.status, recebidos: itens.length });

    let rpc: { status: number; dados: unknown };
    try {
      rpc = await chamarRpc(deps, 'aplicar_atlas', {
        p_itens: itens,
        p_http_status: atlas.status,
        p_iniciado_em: iniciadoEm,
      });
    } catch {
      rpc = { status: 0, dados: null };
    }

    if (rpc.status !== 200 || !rpc.dados || typeof rpc.dados !== 'object') {
      log({ request_id: requestId, etapa: 'aplicar_atlas', http: rpc.status });
      await chamarRpc(deps, 'registrar_falha_atlas', {
        p_http_status: atlas.status,
        p_erro: `falha ao gravar no banco (HTTP ${rpc.status})`,
        p_iniciado_em: iniciadoEm,
      }).catch(() => null);
      return json({ ok: false, etapa: 'banco', http_banco: rpc.status, request_id: requestId }, 500);
    }

    const r = rpc.dados as Record<string, unknown>;
    const resumo = {
      ok: r.ok === true,
      request_id: requestId,
      http_atlas: atlas.status,
      recebidos: r.recebidos,
      gravados: r.gravados,
      sem_placa: r.sem_placa,
      duplicados: r.duplicados,
      desativados: r.desativados,
      posicoes_novas: r.posicoes_novas,
      erro: r.erro ?? null,
    };
    log({ etapa: 'fim', ...resumo });
    // 409 quando a trava dos 50% segurou: aparece como falha nos logs, sem ser erro do código.
    return json(resumo, resumo.ok ? 200 : 409);
  };
}

// No Supabase (Deno) sobe o servidor; nos testes (Node) só exporta o handler.
const deno = (globalThis as { Deno?: { env: { get(n: string): string | undefined }; serve(h: (r: Request) => Promise<Response>): unknown } }).Deno;
if (deno) {
  deno.serve(criarHandler({ env: (n) => deno.env.get(n), fetch: (...a) => fetch(...a) }));
}
