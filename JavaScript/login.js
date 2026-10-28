/**
 * ==========================================================================
 * AJBorges Transportes - Torre de Controle Shopee
 * Tela de login (e-mail e senha do Supabase Auth)
 * ==========================================================================
 */

(function () {
    const app = window.TorreApp;
    const form = document.getElementById('form-login');
    const botao = document.getElementById('btn-entrar');
    const mensagem = document.getElementById('login-mensagem');

    const MENSAGENS = {
        'sem-acesso': 'Seu usuário não tem acesso ao painel. Fale com a gestão.',
        'sem-config': 'Painel sem configuração: preencha a URL e a chave pública em JavaScript/supabase-client.js.',
        'erro': 'Não foi possível conferir seu acesso. Tente de novo.',
        'saiu': 'Você saiu do painel.'
    };

    function mostrar(texto, tipo) {
        mensagem.textContent = texto;
        mensagem.className = 'login-mensagem' + (tipo ? ' ' + tipo : '');
        mensagem.hidden = !texto;
    }

    function ocupado(sim) {
        botao.disabled = sim;
        botao.textContent = sim ? 'Entrando…' : 'Entrar';
    }

    // Motivo vindo do redirecionamento (?motivo=...)
    const motivo = new URLSearchParams(window.location.search).get('motivo');
    if (motivo && MENSAGENS[motivo]) mostrar(MENSAGENS[motivo], motivo === 'saiu' ? 'info' : '');

    if (!app.configurado || !app.supabase) {
        mostrar(MENSAGENS['sem-config']);
        botao.disabled = true;
        return;
    }

    // Já logado e operador: vai direto para o painel.
    app.obterOperador().then(function (r) {
        if (r.operador) window.location.replace('index.html');
    });

    form.addEventListener('submit', async function (evento) {
        evento.preventDefault();
        const email = form.email.value.trim();
        const senha = form.senha.value;
        if (!email || !senha) {
            mostrar('Preencha e-mail e senha.');
            return;
        }

        ocupado(true);
        mostrar('');
        try {
            const { error } = await app.supabase.auth.signInWithPassword({ email: email, password: senha });
            if (error) {
                mostrar('E-mail ou senha incorretos.');
                return;
            }
            const r = await app.obterOperador();
            if (!r.operador) {
                await app.supabase.auth.signOut();
                mostrar(MENSAGENS[r.motivo] || MENSAGENS.erro);
                return;
            }
            window.location.replace('index.html');
        } catch (e) {
            mostrar('Sem conexão com o servidor. Tente de novo.');
        } finally {
            ocupado(false);
        }
    });
})();
