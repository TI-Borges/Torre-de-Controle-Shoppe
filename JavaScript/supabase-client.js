/**
 * ==========================================================================
 * AJBorges Transportes - Torre de Controle Shopee
 * Cliente Supabase, sessão do operador e utilitários comuns às páginas
 * ==========================================================================
 *
 * A Torre usa o Supabase DO SITE (mesmo login dos admins do site). Os dados
 * ficam no schema "torre": toda consulta passa por .schema('torre').
 *
 * Aqui só entram a URL do projeto e a chave PÚBLICA (anon / publishable).
 * Elas são públicas por natureza: quem protege os dados é o RLS do banco.
 * NUNCA coloque aqui a service role / secret key.
 */

// 1. Projeto Supabase do site (Project Settings > API)
const TORRE_SUPABASE = window.TORRE_CONFIG || {
    url: 'https://SEU-PROJETO.supabase.co',
    anonKey: 'COLE_AQUI_A_CHAVE_PUBLICA'
};

const torreConfigurado = !/SEU-PROJETO|COLE_AQUI/.test(TORRE_SUPABASE.url + TORRE_SUPABASE.anonKey);


// 2. Cliente
let torreSupabase = null;
if (window.supabase && typeof window.supabase.createClient === 'function' && torreConfigurado) {
    torreSupabase = window.supabase.createClient(TORRE_SUPABASE.url, TORRE_SUPABASE.anonKey, {
        auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: false }
    });
}


// 3. Utilitários

/** Escapa texto vindo do banco antes de ir para innerHTML. */
function escapeHtml(valor) {
    if (valor === null || valor === undefined) return '';
    return String(valor)
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#39;');
}

/** localStorage pode falhar (aba anônima, bloqueio): nunca deixa a página quebrar. */
function lerPreferencia(chave, padrao) {
    try {
        const bruto = window.localStorage.getItem(chave);
        return bruto === null ? padrao : JSON.parse(bruto);
    } catch (e) {
        return padrao;
    }
}

function salvarPreferencia(chave, valor) {
    try {
        window.localStorage.setItem(chave, JSON.stringify(valor));
    } catch (e) {
        /* sem armazenamento: segue sem salvar */
    }
}

/** Tema: "claro", "escuro" ou null (segue o sistema). */
function aplicarTema(tema) {
    if (tema === 'claro' || tema === 'escuro') {
        document.documentElement.setAttribute('data-tema', tema);
    } else {
        document.documentElement.removeAttribute('data-tema');
    }
}

function temaEfetivo() {
    const definido = document.documentElement.getAttribute('data-tema');
    if (definido) return definido;
    return window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches ? 'escuro' : 'claro';
}

aplicarTema(lerPreferencia('torre.tema', null));


// 4. Sessão do operador

/**
 * Sai só NESTE navegador (scope 'local'). O padrão do supabase-js ('global')
 * derrubaria a sessão da pessoa no site também, em todos os aparelhos (ex.: um
 * motorista que digitou a senha aqui por engano).
 */
async function sair() {
    if (!torreSupabase) return;
    try { await torreSupabase.auth.signOut({ scope: 'local' }); } catch (e) { /* segue */ }
}

/**
 * Devolve { usuario, operador } se houver sessão e o usuário puder ver a Torre:
 * admin do site (claim app_metadata.role) ou operador ativo em torre.operadores.
 * Quem decide é o banco (torre.eh_operador()), o mesmo teste do RLS.
 * Caso contrário devolve { motivo }: 'sem-config', 'sem-sessao', 'sem-acesso',
 * 'sem-schema' ou 'erro'.
 */
async function obterOperador() {
    if (!torreSupabase) return { motivo: 'sem-config' };

    const { data: sessao } = await torreSupabase.auth.getSession();
    const usuario = sessao && sessao.session ? sessao.session.user : null;
    if (!usuario) return { motivo: 'sem-sessao' };

    const [acesso, cadastro] = await Promise.all([
        torreSupabase.schema('torre').rpc('eh_operador'),
        torreSupabase.schema('torre')
            .from('operadores')
            .select('nome, papel, ativo')
            .eq('user_id', usuario.id)
            .maybeSingle()
    ]);

    // PGRST106: o schema torre não está em Data API → Exposed schemas.
    if (acesso.error) return { motivo: acesso.error.code === 'PGRST106' ? 'sem-schema' : 'erro' };
    if (acesso.data !== true) return { motivo: 'sem-acesso' };

    // Admin do site sem cadastro em torre.operadores: nome do Auth ou o e-mail.
    const meta = usuario.user_metadata || {};
    const operador = cadastro.data && cadastro.data.ativo
        ? cadastro.data
        : { nome: meta.nome || usuario.email || 'Administrador', papel: 'admin', ativo: true };
    return { usuario, operador };
}

/** Para as páginas internas: sem sessão ou sem acesso, volta para o login da Torre. */
async function exigirOperador() {
    const r = await obterOperador();
    if (r.operador) return r;

    if (r.motivo === 'sem-acesso') await sair();
    const motivo = r.motivo === 'sem-sessao' ? '' : '?motivo=' + encodeURIComponent(r.motivo);
    window.location.replace('login.html' + motivo);
    return new Promise(() => {}); // a página para aqui até o redirecionamento
}

window.TorreApp = {
    supabase: torreSupabase,
    configurado: torreConfigurado,
    escapeHtml,
    lerPreferencia,
    salvarPreferencia,
    aplicarTema,
    temaEfetivo,
    obterOperador,
    exigirOperador,
    sair
};
