// Testes do painel com puppeteer (1366, 1920 e 390 px).
// As linhas da v_painel vêm do PGlite com os dados de exemplo (mesmo SQL do
// Supabase); o Auth e o REST do Supabase são simulados por interceptação.
// As bibliotecas do CDN são servidas do node_modules (mesmo arquivo do SRI).
//
// Capturas de tela: testes/capturas/ (fora do git).
// Rede de verdade para fontes e mapa (só para olhar as capturas):
//   TORRE_TESTE_REDE=1 npm run test:painel
// Navegador: usa o Chrome instalado; troque com PUPPETEER_EXECUTABLE_PATH.
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { readFile, mkdir } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import path from 'node:path';
import puppeteer from 'puppeteer';
import { criarBanco, lerArquivo, RAIZ } from './apoio/banco.mjs';

const SUPABASE = 'https://teste-local.supabase.co';
const REDE = process.env.TORRE_TESTE_REDE === '1';
const CAPTURAS = path.join(RAIZ, 'testes', 'capturas');

const USUARIOS = {
  'operador@exemplo.invalid': { id: '00000000-0000-4000-8000-0000000000a1', senha: 'senha-teste', operador: { nome: 'Operador Teste', papel: 'operador', ativo: true } },
  'semacesso@exemplo.invalid': { id: '00000000-0000-4000-8000-0000000000b2', senha: 'senha-teste', operador: null },
};

const CDN = {
  'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.117.3/dist/umd/supabase.js': 'node_modules/@supabase/supabase-js/dist/umd/supabase.js',
  'https://cdn.jsdelivr.net/npm/leaflet@1.9.4/dist/leaflet.js': 'node_modules/leaflet/dist/leaflet.js',
  'https://cdn.jsdelivr.net/npm/leaflet@1.9.4/dist/leaflet.css': 'node_modules/leaflet/dist/leaflet.css',
  'https://cdn.jsdelivr.net/npm/leaflet.markercluster@1.5.3/dist/leaflet.markercluster.js': 'node_modules/leaflet.markercluster/dist/leaflet.markercluster.js',
  'https://cdn.jsdelivr.net/npm/leaflet.markercluster@1.5.3/dist/MarkerCluster.css': 'node_modules/leaflet.markercluster/dist/MarkerCluster.css',
};

const PNG_1PX = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8/x8AAwMCAO+ip1sAAAAASUVORK5CYII=', 'base64');

let servidor, base, navegador, linhasPainel, parametros;

// ---------------------------------------------------------------------------
// Preparação
// ---------------------------------------------------------------------------

before(async () => {
  // Linhas da v_painel a partir dos dados de exemplo (como o PostgREST devolve)
  const db = await criarBanco();
  await db.exec(await lerArquivo('supabase/sql/dados_exemplo.sql'));
  linhasPainel = (await db.query(`select coalesce(json_agg(v), '[]') as l from public.v_painel v`)).rows[0].l;
  parametros = (await db.query(`select coalesce(json_agg(p), '[]') as l from public.parametros p`)).rows[0].l;
  // texto malicioso num nome para provar o escapeHtml
  linhasPainel.find((l) => l.placa === 'TSTE002').motorista_nome = '<img src=x onerror="window.__xss=1">Motorista Exemplo 02';

  servidor = http.createServer(async (req, res) => {
    const caminho = path.join(RAIZ, decodeURIComponent(new URL(req.url, 'http://x').pathname));
    if (!caminho.startsWith(RAIZ) || !existsSync(caminho)) { res.writeHead(404).end(); return; }
    const tipo = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css' }[path.extname(caminho)] || 'application/octet-stream';
    res.writeHead(200, { 'Content-Type': tipo + '; charset=utf-8' }).end(await readFile(caminho));
  });
  await new Promise((r) => servidor.listen(0, '127.0.0.1', r));
  base = `http://127.0.0.1:${servidor.address().port}`;

  await mkdir(CAPTURAS, { recursive: true });
  const executablePath = process.env.PUPPETEER_EXECUTABLE_PATH ||
    ['C:/Program Files/Google/Chrome/Application/chrome.exe', 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe']
      .find((p) => existsSync(p));
  navegador = await puppeteer.launch({ headless: true, executablePath });
});

after(async () => {
  await navegador?.close();
  servidor?.close();
});

// ---------------------------------------------------------------------------
// Supabase simulado
// ---------------------------------------------------------------------------

function jwt(usuario) {
  const b64 = (o) => Buffer.from(JSON.stringify(o)).toString('base64url');
  return [b64({ alg: 'HS256', typ: 'JWT' }),
    b64({ sub: usuario.id, aud: 'authenticated', role: 'authenticated', email: usuario.email, exp: Math.floor(Date.now() / 1000) + 3600 }),
    'assinatura-de-teste'].join('.');
}

function usuarioPublico(u) {
  return { id: u.id, aud: 'authenticated', role: 'authenticated', email: u.email, app_metadata: {}, user_metadata: {}, created_at: '2026-01-01T00:00:00Z' };
}

async function novaPagina({ largura, altura, sincronizacaoMin = 5, intervaloRapido = false }) {
  const contexto = await navegador.createBrowserContext();
  const pagina = await contexto.newPage();
  pagina.on('close', () => contexto.close().catch(() => {}));
  await pagina.setViewport({ width: largura, height: altura });
  const registro = { painel: 0, erros: [] };
  pagina.on('pageerror', (e) => registro.erros.push(e.message));

  await pagina.evaluateOnNewDocument((config, rapido) => {
    window.TORRE_CONFIG = config;
    // expõe o mapa para o teste conferir zoom e centro
    document.addEventListener('DOMContentLoaded', () => {
      if (window.L) window.L.Map.addInitHook(function () { window.__mapaTeste = this; });
    });
    if (rapido) {
      const original = window.setInterval;
      window.setInterval = (fn, ms, ...r) => original(fn, ms === 60000 ? 400 : ms, ...r);
      const desc = Object.getOwnPropertyDescriptor(Document.prototype, 'hidden');
      Object.defineProperty(document, 'hidden', { get: () => window.__abaOculta === true || desc.get.call(document) });
    }
  }, { url: SUPABASE, anonKey: 'chave-publica-de-teste' }, intervaloRapido);

  await pagina.setRequestInterception(true);
  pagina.on('request', async (req) => {
    const url = req.url();
    const cors = {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Headers': req.headers()['access-control-request-headers'] || '*',
      'Access-Control-Allow-Methods': 'GET, POST, PATCH, DELETE, OPTIONS',
      'Access-Control-Expose-Headers': 'content-range',
    };
    const responder = (status, corpo, tipo = 'application/json') =>
      req.respond({ status, headers: cors, contentType: tipo, body: typeof corpo === 'string' || Buffer.isBuffer(corpo) ? corpo : JSON.stringify(corpo) });

    try {
      if (CDN[url]) return responder(200, await readFile(path.join(RAIZ, CDN[url])), url.endsWith('.css') ? 'text/css' : 'text/javascript');
      if (/fonts\.(googleapis|gstatic)\.com/.test(url)) return REDE ? req.continue() : responder(200, '', 'text/css');
      if (/tile\.openstreetmap\.org/.test(url)) return REDE ? req.continue() : responder(200, PNG_1PX, 'image/png');
      if (!url.startsWith(SUPABASE)) return req.continue();
      if (req.method() === 'OPTIONS') return responder(204, '');

      const u = new URL(url);
      const token = (req.headers()['authorization'] || '').replace(/^Bearer /, '');
      // sem login, o cliente manda a chave pública (que não é JWT) no Authorization
      const claims = decodificar(token);
      const logado = claims && Object.entries(USUARIOS).map(([email, d]) => ({ email, ...d }))
        .find((x) => x.id === claims.sub);

      if (u.pathname === '/auth/v1/token') {
        const { email, password } = JSON.parse(req.postData() || '{}');
        const d = USUARIOS[email];
        if (!d || d.senha !== password) return responder(400, { error: 'invalid_grant', error_description: 'Invalid login credentials', code: 'invalid_credentials' });
        const usuario = { ...d, email };
        return responder(200, {
          access_token: jwt(usuario), token_type: 'bearer', expires_in: 3600,
          expires_at: Math.floor(Date.now() / 1000) + 3600, refresh_token: 'refresh-de-teste', user: usuarioPublico(usuario),
        });
      }
      if (u.pathname === '/auth/v1/user') return logado ? responder(200, usuarioPublico(logado)) : responder(401, { msg: 'sem sessão' });
      if (u.pathname === '/auth/v1/logout') return responder(204, '');

      // REST: sem token de usuário, o RLS não devolveria nada
      if (u.pathname === '/rest/v1/operadores') {
        const linha = logado?.operador ? [logado.operador] : [];
        return responder(200, linha);
      }
      if (u.pathname === '/rest/v1/v_painel') {
        registro.painel++;
        return responder(200, logado?.operador ? linhasPainel : []);
      }
      if (u.pathname === '/rest/v1/sincronizacao') {
        const t = new Date(Date.now() - sincronizacaoMin * 60000).toISOString();
        return responder(200, logado?.operador ? [{ terminado_em: t, erro: null }] : []);
      }
      if (u.pathname === '/rest/v1/parametros') return responder(200, logado?.operador ? parametros : []);
      return responder(404, { message: 'rota não simulada: ' + u.pathname });
    } catch (e) {
      registro.erros.push('interceptação: ' + e.message);
      return req.abort();
    }
  });
  return { pagina, registro };
}

function decodificar(token) {
  try { return JSON.parse(Buffer.from(token.split('.')[1], 'base64url').toString()); } catch { return null; }
}

async function entrar(pagina, email, senha = 'senha-teste') {
  await pagina.goto(`${base}/HTML/login.html`, { waitUntil: 'domcontentloaded' });
  await pagina.type('#email', email);
  await pagina.type('#senha', senha);
  await pagina.click('#btn-entrar');
}

async function esperarPainel(pagina) {
  await pagina.waitForFunction(() => location.pathname.endsWith('/HTML/index.html'), { timeout: 15000 });
  await pagina.waitForFunction(() => document.querySelectorAll('#tabela-corpo tr').length > 0 &&
    !document.body.classList.contains('carregando'), { timeout: 15000 });
}

const linhasTabela = (p) => p.$$eval('#tabela-corpo tr', (trs) => trs.length);

// veículos no mapa = marcadores soltos + soma dos números dos grupos
const veiculosNoMapa = (p) => p.evaluate(() => {
  const soltos = document.querySelectorAll('.leaflet-marker-icon.marcador').length;
  const agrupados = [...document.querySelectorAll('.leaflet-marker-icon.agrupado span')].reduce((s, e) => s + Number(e.textContent), 0);
  return soltos + agrupados;
});

const valorKpi = (p, rotulo) => p.evaluate((r) => {
  const b = [...document.querySelectorAll('.kpi')].find((k) => k.querySelector('.kpi-rotulo').textContent === r);
  return b ? Number(b.querySelector('.kpi-valor').textContent) : null;
}, rotulo);

const clicarKpi = (p, rotulo) => p.evaluate((r) => {
  [...document.querySelectorAll('.kpi')].find((k) => k.querySelector('.kpi-rotulo').textContent === r).click();
}, rotulo);

async function digitarBusca(p, texto) {
  await p.$eval('#busca', (e) => { e.value = ''; e.dispatchEvent(new Event('input', { bubbles: true })); });
  if (texto) await p.type('#busca', texto);
  await new Promise((r) => setTimeout(r, 300));
}

// ---------------------------------------------------------------------------
// Testes
// ---------------------------------------------------------------------------

test('login obrigatório: sem sessão o painel volta para o login', async () => {
  const { pagina } = await novaPagina({ largura: 1366, altura: 768 });
  await pagina.goto(`${base}/HTML/index.html`, { waitUntil: 'domcontentloaded' });
  await pagina.waitForFunction(() => location.pathname.endsWith('/HTML/login.html'), { timeout: 10000 });
  await pagina.close();
});

test('login: senha errada e usuário sem cadastro de operador não entram', async () => {
  const { pagina } = await novaPagina({ largura: 1366, altura: 768 });
  await entrar(pagina, 'operador@exemplo.invalid', 'errada');
  await pagina.waitForSelector('#login-mensagem:not([hidden])');
  assert.match(await pagina.$eval('#login-mensagem', (e) => e.textContent), /incorretos/);

  await pagina.reload({ waitUntil: 'domcontentloaded' });
  await entrar(pagina, 'semacesso@exemplo.invalid');
  await pagina.waitForFunction(() => /não tem acesso/.test(document.querySelector('#login-mensagem').textContent));
  assert.ok(pagina.url().endsWith('/HTML/login.html'));
  // e não ficou sessão salva: abrir o painel volta para o login
  await pagina.goto(`${base}/HTML/index.html`, { waitUntil: 'domcontentloaded' });
  await pagina.waitForFunction(() => location.pathname.endsWith('/HTML/login.html'), { timeout: 10000 });
  await pagina.close();
});

for (const [largura, altura] of [[1366, 768], [1920, 1080], [390, 844]]) {
  test(`painel em ${largura}px: KPIs, filtros, mapa, popup e tabela`, async () => {
    const { pagina, registro } = await novaPagina({ largura, altura });
    await entrar(pagina, 'operador@exemplo.invalid');
    await esperarPainel(pagina);
    await pagina.waitForFunction(() => document.querySelectorAll('.leaflet-marker-icon').length > 0);
    await new Promise((r) => setTimeout(r, 600));
    await pagina.screenshot({ path: path.join(CAPTURAS, `painel-${largura}.png`), fullPage: largura === 390 });

    // KPIs
    assert.equal(await valorKpi(pagina, 'Total ativos'), 29);
    assert.equal(await valorKpi(pagina, 'Erro API Atlas'), 3);
    assert.equal(await valorKpi(pagina, 'Sem SM'), 5);
    assert.equal(await valorKpi(pagina, 'Posição desatualizada'), 4);
    for (const v of ['Frota', 'Terceiro', 'Agregado']) assert.ok((await valorKpi(pagina, v)) > 0, v);
    const status = await pagina.$$eval('.kpi[data-grupo="status"]', (b) => b.map((x) => x.dataset.valor).sort());
    assert.deepEqual(status, ['Carregando', 'Em Descarga', 'Em Viagem Carregado', 'Em Viagem Vazio', 'Sem Viagem']);
    assert.equal((await valorKpi(pagina, 'Em movimento')) + (await valorKpi(pagina, 'Parados')), 28);

    // Tabela e mapa com tudo
    assert.equal(await linhasTabela(pagina), 29);
    assert.equal(await veiculosNoMapa(pagina), 28, 'o veículo sem posição não vai para o mapa');
    assert.equal(await pagina.$$eval('#tabela-corpo tr.linha-atrasada', (t) => t.length), 4);

    // Posição atrasada: faixa à esquerda e fundo claro, nunca vermelho
    const estilo = await pagina.$eval('#tabela-corpo tr.linha-atrasada', (tr) => {
      const alvo = getComputedStyle(tr).display === 'grid' ? tr : tr.querySelector('td');
      const cs = getComputedStyle(alvo);
      return { sombra: cs.boxShadow, fundo: cs.backgroundColor };
    });
    assert.match(estilo.sombra, /inset/);
    const [r, g, b] = estilo.fundo.match(/\d+/g).map(Number);
    assert.ok(r > 240 && g > 230 && b > 200, 'fundo claro: ' + estilo.fundo);

    // escapeHtml: o nome com <img onerror> aparece como texto e não executa
    assert.equal(await pagina.evaluate(() => window.__xss), undefined);
    assert.ok(await pagina.evaluate(() => document.querySelector('#tabela-corpo').textContent.includes('<img src=x')));

    // Filtro por KPI: Erro API Atlas
    await clicarKpi(pagina, 'Erro API Atlas');
    assert.equal(await linhasTabela(pagina), 3);
    assert.equal(await veiculosNoMapa(pagina), 3);
    assert.equal(await pagina.$$eval('.chip', (c) => c.length), 1);
    assert.equal(await pagina.$eval('.kpi[data-valor="erro_api"]', (b) => b.getAttribute('aria-pressed')), 'true');

    // soma com outro grupo (E) e dentro do grupo (OU)
    await clicarKpi(pagina, 'Sem SM');
    assert.equal(await linhasTabela(pagina), 8);
    await pagina.click('#btn-limpar');
    assert.equal(await linhasTabela(pagina), 29);

    // Busca por placa (com traço), motorista, cidade e SM
    await digitarBusca(pagina, 'tste-003');
    assert.equal(await linhasTabela(pagina), 1);
    await digitarBusca(pagina, 'exemplo 07');
    assert.equal(await linhasTabela(pagina), 1);
    await digitarBusca(pagina, 'curitiba');
    assert.equal(await linhasTabela(pagina), 1);
    await digitarBusca(pagina, '9900013');
    assert.equal(await linhasTabela(pagina), 1);
    assert.equal(await veiculosNoMapa(pagina), 1);
    await digitarBusca(pagina, '');

    // Botões de parados e de atrasados
    await clicarKpi(pagina, 'Parados');
    const parados = await valorKpi(pagina, 'Parados');
    assert.equal(await linhasTabela(pagina), parados);
    await clicarKpi(pagina, 'Parados');
    await clicarKpi(pagina, 'Posição desatualizada');
    assert.equal(await linhasTabela(pagina), 4);
    await clicarKpi(pagina, 'Frota');
    assert.ok((await linhasTabela(pagina)) < 4);

    // Filtros ficam salvos neste navegador
    await pagina.reload({ waitUntil: 'domcontentloaded' });
    await esperarPainel(pagina);
    assert.equal(await pagina.$eval('.kpi[data-grupo="atrasados"]', (b) => b.getAttribute('aria-pressed')), 'true');
    assert.equal(await pagina.$eval('.kpi[data-valor="FROTA"]', (b) => b.getAttribute('aria-pressed')), 'true');
    await pagina.click('#btn-limpar');
    assert.equal(await linhasTabela(pagina), 29);

    // Clicar na tabela centraliza no mapa e abre o popup
    await pagina.click('#tabela-corpo tr[data-placa="TSTE017"]');
    await pagina.waitForFunction(() => document.querySelector('.leaflet-popup-content .popup')?.textContent.includes('TSTE017'), { timeout: 10000 });
    const popup = await pagina.$eval('.leaflet-popup-content', (e) => e.textContent);
    for (const trecho of ['TSTE017', 'Motorista Exemplo 17', 'Curitiba/PR', 'km/h', 'Macro', 'Posição']) assert.ok(popup.includes(trecho), trecho);
    await new Promise((r) => setTimeout(r, 400));
    await pagina.screenshot({ path: path.join(CAPTURAS, `popup-${largura}.png`) });

    // Clicar no marcador seleciona a linha da tabela
    await pagina.click('.leaflet-popup-close-button');
    await pagina.evaluate(() => document.querySelectorAll('#tabela-corpo tr.selecionada').forEach((tr) => tr.classList.remove('selecionada')));
    const marcador017 = await pagina.evaluateHandle(() =>
      [...document.querySelectorAll('.leaflet-marker-icon.marcador')].find((e) => e.title.startsWith('TSTE017')));
    assert.ok(marcador017.asElement(), 'marcador do TSTE017 visível');
    await marcador017.asElement().click();
    await pagina.waitForFunction(() => document.querySelector('#tabela-corpo tr.selecionada')?.dataset.placa === 'TSTE017');
    await pagina.waitForFunction(() => document.querySelector('.leaflet-popup-content')?.textContent.includes('TSTE017'));

    if (largura === 390) {
      const semRolagemLateral = await pagina.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth);
      assert.ok(semRolagemLateral, 'sem rolagem horizontal no celular');
      assert.equal(await pagina.$eval('#tabela-corpo tr', (tr) => getComputedStyle(tr).display), 'grid', 'tabela vira cards');
      assert.equal(await pagina.$eval('#tabela thead', (t) => getComputedStyle(t).display), 'none');
    } else {
      assert.equal(await pagina.$eval('#tabela thead th', (th) => getComputedStyle(th).position), 'sticky');
    }

    // Ordenação por km/h (desc no 2º clique)
    if (largura !== 390) {
      await pagina.click('#tabela th[data-col="velocidade"]');
      await pagina.click('#tabela th[data-col="velocidade"]');
      assert.equal(await pagina.$eval('#tabela th[data-col="velocidade"]', (th) => th.getAttribute('aria-sort')), 'descending');
      const vels = await pagina.$$eval('#tabela-corpo tr td.num', (tds) => tds.map((t) => Number(t.textContent)).filter((n) => !isNaN(n)));
      assert.deepEqual(vels, [...vels].sort((a, b) => b - a));
    }

    // Modo TV
    if (largura !== 390) {
      await pagina.click('#btn-tv');
      assert.ok(await pagina.evaluate(() => document.body.classList.contains('modo-tv')));
      await new Promise((r) => setTimeout(r, 500));
      await pagina.screenshot({ path: path.join(CAPTURAS, `modo-tv-${largura}.png`) });
      await pagina.click('#btn-tv');
    }

    // Tema escuro
    await pagina.click('#btn-tema');
    await new Promise((r) => setTimeout(r, 300));
    await pagina.screenshot({ path: path.join(CAPTURAS, `escuro-${largura}.png`), fullPage: largura === 390 });
    await pagina.click('#btn-tema');

    assert.deepEqual(registro.erros, []);
    await pagina.close();
  });
}

test('aviso de dados atrasados: "Atualizado às" fica vermelho depois de 35 min', async () => {
  const fresco = await novaPagina({ largura: 1366, altura: 768, sincronizacaoMin: 5 });
  await entrar(fresco.pagina, 'operador@exemplo.invalid');
  await esperarPainel(fresco.pagina);
  const ok = await fresco.pagina.$eval('#atualizado', (e) => ({ texto: e.textContent, atrasado: e.classList.contains('atrasado') }));
  assert.match(ok.texto, /^Atualizado às \d{2}:\d{2}$/);
  assert.equal(ok.atrasado, false);
  await fresco.pagina.close();

  const velho = await novaPagina({ largura: 1366, altura: 768, sincronizacaoMin: 50 });
  await entrar(velho.pagina, 'operador@exemplo.invalid');
  await esperarPainel(velho.pagina);
  const ruim = await velho.pagina.$eval('#atualizado', (e) => ({ texto: e.textContent, atrasado: e.classList.contains('atrasado'), cor: getComputedStyle(e).backgroundColor }));
  assert.equal(ruim.atrasado, true);
  assert.match(ruim.texto, /há 50 min/);
  assert.equal(ruim.cor, 'rgb(220, 38, 38)');
  await velho.pagina.screenshot({ path: path.join(CAPTURAS, 'dados-atrasados.png'), clip: { x: 0, y: 0, width: 1366, height: 80 } });
  await velho.pagina.close();
});

test('atualização periódica: mantém filtros, rolagem e zoom; parada com a aba oculta', async () => {
  const { pagina, registro } = await novaPagina({ largura: 1366, altura: 768, intervaloRapido: true });
  await entrar(pagina, 'operador@exemplo.invalid');
  await esperarPainel(pagina);

  await clicarKpi(pagina, 'Em movimento');
  const linhas = await linhasTabela(pagina);
  await new Promise((r) => setTimeout(r, 800)); // fim da animação do enquadramento inicial
  await pagina.evaluate(() => { window.__mapaTeste.setView([-23.35, -46.88], 12, { animate: false }); });
  await pagina.$eval('#tabela-rolagem', (e) => { e.style.maxHeight = '200px'; e.scrollTop = 120; });

  const antes = registro.painel;
  await new Promise((r) => setTimeout(r, 1500));
  assert.ok(registro.painel >= antes + 2, `atualizou ${registro.painel - antes} vezes`);

  assert.equal(await linhasTabela(pagina), linhas);
  assert.equal(await pagina.$eval('.kpi[data-valor="movimento"]', (b) => b.getAttribute('aria-pressed')), 'true');
  assert.equal(await pagina.$eval('#tabela-rolagem', (e) => e.scrollTop), 120);
  const vista = await pagina.evaluate(() => ({ z: window.__mapaTeste.getZoom(), c: window.__mapaTeste.getCenter() }));
  assert.equal(vista.z, 12);
  assert.ok(Math.abs(vista.c.lat + 23.35) < 0.001 && Math.abs(vista.c.lng + 46.88) < 0.001);

  // aba oculta: não busca
  await pagina.evaluate(() => { window.__abaOculta = true; });
  await new Promise((r) => setTimeout(r, 300));
  const congelado = registro.painel;
  await new Promise((r) => setTimeout(r, 1500));
  assert.equal(registro.painel, congelado);
  await pagina.close();
});
