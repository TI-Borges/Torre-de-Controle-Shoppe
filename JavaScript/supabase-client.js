/**
 * ==========================================================================
 * AJBorges Transportes - Torre de Controle Shopee
 * Cliente Supabase, sessão do operador e utilitários comuns às páginas
 * ==========================================================================
 *
 * Aqui só entram a URL do projeto e a chave PÚBLICA (anon / publishable).
 * Elas são públicas por natureza: quem protege os dados é o RLS do banco.
 * NUNCA coloque aqui a service role / secret key.
 */

// 1. Projeto Supabase da Torre de Controle (Project Settings > API)
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
 * Devolve { usuario, operador } se houver sessão e o usuário for operador ativo.
 * Caso contrário devolve { motivo }: 'sem-config', 'sem-sessao', 'sem-acesso' ou 'erro'.
 */
async function obterOperador() {
    if (!torreSupabase) return { motivo: 'sem-config' };

    const { data: sessao } = await torreSupabase.auth.getSession();
    const usuario = sessao && sessao.session ? sessao.session.user : null;
    if (!usuario) return { motivo: 'sem-sessao' };

    const { data, error } = await torreSupabase
        .from('operadores')
        .select('nome, papel, ativo')
        .eq('user_id', usuario.id)
        .maybeSingle();

    if (error) return { motivo: 'erro' };
    if (!data || !data.ativo) return { motivo: 'sem-acesso' };
    return { usuario, operador: data };
}

/** Para as páginas internas: sem sessão ou sem ser operador, volta para o login. */
async function exigirOperador() {
    const r = await obterOperador();
    if (r.operador) return r;

    if (r.motivo === 'sem-acesso' && torreSupabase) await torreSupabase.auth.signOut();
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
    exigirOperador
};
