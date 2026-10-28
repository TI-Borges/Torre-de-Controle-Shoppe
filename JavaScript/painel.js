/**
 * ==========================================================================
 * AJBorges Transportes - Torre de Controle Shopee
 * Painel: KPIs, mapa (Leaflet + markercluster), tabela e filtros
 * ==========================================================================
 *
 * Lê a view torre.v_painel (o RLS só libera para admin do site ou operador ativo).
 * Tudo que vem do banco passa por escapeHtml antes de ir para o HTML.
 */

(function () {
    'use strict';

    const app = window.TorreApp;
    const sb = app.supabase;
    const esc = app.escapeHtml;
    const $ = function (id) { return document.getElementById(id); };

    const INTERVALO_MS = 60 * 1000;
    const CHAVE_FILTROS = 'torre.filtros.v1';
    const CHAVE_ORDEM = 'torre.ordem.v1';
    const CHAVE_TV = 'torre.tv';
    const FUSO = 'America/Sao_Paulo';

    // Cores fixas para os status conhecidos; os novos ganham uma cor da paleta extra.
    const CORES_STATUS = {
        'em viagem carregado': '#16a34a',
        'em viagem vazio': '#0891b2',
        'carregando': '#2563eb',
        'em descarga': '#7c3aed',
        'sem viagem': '#64748b'
    };
    const PALETA_EXTRA = ['#d97706', '#db2777', '#0d9488', '#9333ea', '#ca8a04', '#4f46e5', '#be123c'];
    const VINCULOS = ['FROTA', 'TERCEIRO', 'AGREGADO'];
    const SEM_STATUS = '(sem status)';
    const SEM_VINCULO = '(sem vínculo)';

    const estado = {
        linhas: [],
        parametros: { minutos_sincronizacao_atrasada: 35, minutos_posicao_atrasada: 30 },
        filtros: normalizarFiltros(app.lerPreferencia(CHAVE_FILTROS, {})),
        ordem: normalizarOrdem(app.lerPreferencia(CHAVE_ORDEM, null)),
        selecionada: null,
        popupAberto: null,
        ultimaCarga: 0,
        carregando: false,
        primeiraCarga: true,
        tvTelaCheia: false,
        marcadores: new Map()
    };

    let mapa = null;
    let grupo = null;


    // ----------------------------------------------------------------------
    // Utilitários
    // ----------------------------------------------------------------------

    function normalizarFiltros(f) {
        f = f && typeof f === 'object' ? f : {};
        const lista = function (v) { return Array.isArray(v) ? v.filter(function (x) { return typeof x === 'string'; }) : []; };
        return {
            busca: typeof f.busca === 'string' ? f.busca : '',
            status: lista(f.status),
            vinculo: lista(f.vinculo),
            eta: lista(f.eta),
            movimento: f.movimento === 'movimento' || f.movimento === 'parado' ? f.movimento : null,
            atrasados: f.atrasados === true
        };
    }

    function normalizarOrdem(o) {
        const colunas = ['placa', 'placa_carreta', 'motorista_nome', 'vinculo', 'status_operacional', 'macro_vigente',
            'velocidade', 'cidade_uf', 'localizacao_atual', 'destino_nome', 'eta', 'minutos_sem_posicao'];
        if (o && colunas.indexOf(o.col) >= 0 && (o.dir === 'asc' || o.dir === 'desc')) return o;
        return { col: 'placa', dir: 'asc' };
    }

    function temFiltro(f) {
        return !!(f.busca.trim() || f.status.length || f.vinculo.length || f.eta.length || f.movimento || f.atrasados);
    }

    function semAcento(texto) {
        return String(texto || '').normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase();
    }

    function corStatus(status) {
        const chave = semAcento(status).trim();
        if (CORES_STATUS[chave]) return CORES_STATUS[chave];
        let h = 0;
        for (let i = 0; i < chave.length; i++) h = (h * 31 + chave.charCodeAt(i)) >>> 0;
        return PALETA_EXTRA[h % PALETA_EXTRA.length];
    }

    const fmtHora = new Intl.DateTimeFormat('pt-BR', { timeZone: FUSO, hour: '2-digit', minute: '2-digit' });
    const fmtDiaHora = new Intl.DateTimeFormat('pt-BR', { timeZone: FUSO, day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' });

    function hora(iso) { return iso ? fmtHora.format(new Date(iso)) : ''; }
    function diaHora(iso) { return iso ? fmtDiaHora.format(new Date(iso)).replace(',', '') : ''; }

    function minutosDesde(iso) {
        if (!iso) return null;
        return Math.max(0, Math.floor((Date.now() - new Date(iso).getTime()) / 60000));
    }

    function idade(min) {
        if (min === null) return 'sem posição';
        if (min < 1) return 'agora';
        if (min < 60) return 'há ' + min + ' min';
        if (min < 1440) {
            const h = Math.floor(min / 60);
            const m = min % 60;
            return 'há ' + h + ' h' + (m ? ' ' + m + ' min' : '');
        }
        return 'há ' + Math.floor(min / 1440) + ' d';
    }

    function placaVisivel(l) {
        return l.tem_placa ? l.placa : 'Sem placa';
    }

    function badgeStatus(status) {
        return '<span class="badge" style="--cor:' + corStatus(status) + '">' + esc(status) + '</span>';
    }

    function textoEta(l) {
        if (l.eta_situacao === 'ok') return '<span class="eta-ok">' + esc(diaHora(l.destino_eta_real)) + '</span>';
        if (l.eta_situacao === 'erro_api') return '<span class="tag tag-perigo">Erro API Atlas</span>';
        if (l.eta_situacao === 'sem_sm') return '<span class="tag tag-neutra">Sem SM</span>';
        return l.destino_eta_real ? esc(diaHora(l.destino_eta_real)) : '<span class="vazio">—</span>';
    }

    function ou(valor) {
        return valor === null || valor === undefined || valor === '' ? '<span class="vazio">—</span>' : esc(valor);
    }

    function velocidade(l) {
        if (l.velocidade === null || l.velocidade === undefined) return null;
        return Math.round(Number(l.velocidade));
    }


    // ----------------------------------------------------------------------
    // Dados
    // ----------------------------------------------------------------------

    function preparar(l) {
        l._status = l.status_operacional || SEM_STATUS;
        l._vinculo = (l.vinculo || '').toUpperCase() || SEM_VINCULO;
        l._min = minutosDesde(l.data_ultima_posicao);
        const campos = [l.placa, l.placa_carreta, l.frota_cavalo, l.motorista_nome, l.cidade_uf, l.codigo_sm, l.localizacao_atual];
        l._busca = semAcento(campos.join(' '));
        l._buscaCompacta = l._busca.replace(/[^a-z0-9]/g, '');
        return l;
    }

    function passa(l, f) {
        if (f.status.length && f.status.indexOf(l._status) < 0) return false;
        if (f.vinculo.length && f.vinculo.indexOf(l._vinculo) < 0) return false;
        if (f.eta.length && f.eta.indexOf(l.eta_situacao) < 0) return false;
        if (f.movimento === 'movimento' && !l.em_movimento) return false;
        if (f.movimento === 'parado' && !l.parado) return false;
        if (f.atrasados && !l.posicao_atrasada) return false;
        const q = semAcento(f.busca).trim();
        if (q) {
            const qc = q.replace(/[^a-z0-9]/g, '');
            if (l._busca.indexOf(q) < 0 && !(qc && l._buscaCompacta.indexOf(qc) >= 0)) return false;
        }
        return true;
    }

    const ORDEM_ETA = { ok: 0, erro_api: 1, sem_sm: 2 };

    function comparar(a, b) {
        const col = estado.ordem.col;
        const dir = estado.ordem.dir === 'asc' ? 1 : -1;
        let va, vb;

        if (col === 'velocidade') {
            va = velocidade(a); vb = velocidade(b);
        } else if (col === 'minutos_sem_posicao') {
            va = a._min; vb = b._min;
        } else if (col === 'eta') {
            const ga = a.eta_situacao in ORDEM_ETA ? ORDEM_ETA[a.eta_situacao] : 3;
            const gb = b.eta_situacao in ORDEM_ETA ? ORDEM_ETA[b.eta_situacao] : 3;
            if (ga !== gb) return ga - gb;
            va = a.destino_eta_real ? Date.parse(a.destino_eta_real) : null;
            vb = b.destino_eta_real ? Date.parse(b.destino_eta_real) : null;
        } else {
            va = col === 'vinculo' ? a._vinculo : col === 'status_operacional' ? a._status : a[col];
            vb = col === 'vinculo' ? b._vinculo : col === 'status_operacional' ? b._status : b[col];
            va = va === null || va === undefined || va === '' ? null : String(va);
            vb = vb === null || vb === undefined || vb === '' ? null : String(vb);
        }

        // vazios sempre no fim
        if (va === null && vb === null) return String(a.placa).localeCompare(String(b.placa));
        if (va === null) return 1;
        if (vb === null) return -1;
        if (typeof va === 'number') return (va - vb) * dir || String(a.placa).localeCompare(String(b.placa));
        return va.localeCompare(vb, 'pt-BR', { numeric: true, sensitivity: 'base' }) * dir;
    }

    async function carregar() {
        if (estado.carregando) return;
        estado.carregando = true;
        try {
            const consultas = [
                sb.schema('torre').from('v_painel').select('*').limit(5000),
                sb.schema('torre').from('sincronizacao').select('terminado_em, erro').order('id', { ascending: false }).limit(20)
            ];
            if (estado.primeiraCarga) consultas.push(sb.schema('torre').from('parametros').select('chave, valor'));
            const r = await Promise.all(consultas);

            if (r[0].error) throw r[0].error;
            if (r[2] && r[2].data) {
                r[2].data.forEach(function (p) {
                    const n = parseInt(p.valor, 10);
                    if (!isNaN(n)) estado.parametros[p.chave] = n;
                });
            }

            estado.linhas = (r[0].data || []).map(preparar);
            renderAtualizado(r[1].error ? [] : (r[1].data || []));
            renderTudo();
            esconderAviso();
        } catch (e) {
            const codigo = e && (e.status || e.code);
            if (codigo === 401 || codigo === 'PGRST301') {
                await app.exigirOperador();
                return;
            }
            mostrarAviso('Não foi possível atualizar os dados agora. Nova tentativa em 1 minuto.');
        } finally {
            estado.carregando = false;
            estado.ultimaCarga = Date.now();
            if (estado.primeiraCarga) {
                estado.primeiraCarga = false;
                document.body.classList.remove('carregando');
            }
        }
    }


    // ----------------------------------------------------------------------
    // Renderização
    // ----------------------------------------------------------------------

    function renderTudo() {
        const visiveis = estado.linhas.filter(function (l) { return passa(l, estado.filtros); }).sort(comparar);
        renderKpis();
        renderFiltrosAtivos(visiveis.length);
        renderTabela(visiveis);
        renderMapa(visiveis);
        renderLegenda(visiveis);
    }

    function renderAtualizado(sincs) {
        const el = $('atualizado');
        const boa = sincs.find(function (s) { return !s.erro && s.terminado_em; });
        const ultima = sincs[0];
        const limite = estado.parametros.minutos_sincronizacao_atrasada;
        const min = boa ? minutosDesde(boa.terminado_em) : null;
        const atrasado = min === null || min > limite;

        let titulo;
        if (boa) {
            el.textContent = 'Atualizado às ' + hora(boa.terminado_em) + (atrasado ? ' · ' + idade(min) : '');
            titulo = 'Última sincronização boa com o Atlas: ' + diaHora(boa.terminado_em) + ' (' + idade(min) + '). ' +
                     'A busca no Atlas é a cada 15 min; fica vermelho depois de ' + limite + ' min.';
        } else {
            el.textContent = 'Sem sincronização';
            titulo = 'Nenhuma sincronização boa com o Atlas foi registrada.';
        }
        if (ultima && ultima.erro) titulo += ' Última tentativa falhou: ' + ultima.erro;
        el.title = titulo;
        el.classList.toggle('atrasado', atrasado);
        el.classList.toggle('com-falha', !!(ultima && ultima.erro));
    }

    function contar(predicado) {
        let n = 0;
        estado.linhas.forEach(function (l) { if (predicado(l)) n++; });
        return n;
    }

    function cartaoKpi(c) {
        const ativo = c.ativo ? 'true' : 'false';
        const cor = c.cor ? ' style="--cor:' + c.cor + '"' : '';
        return '<button type="button" class="kpi' + (c.tom ? ' kpi-' + c.tom : '') + (c.cor ? ' kpi-cor' : '') + '"' + cor +
               ' data-grupo="' + esc(c.grupo) + '" data-valor="' + esc(c.valor) + '" aria-pressed="' + ativo + '">' +
               '<span class="kpi-rotulo">' + esc(c.rotulo) + '</span>' +
               '<span class="kpi-valor">' + c.qtd + '</span></button>';
    }

    function renderKpis() {
        const f = estado.filtros;
        const L = estado.linhas;

        // status: os que vierem, do mais frequente para o menos
        const porStatus = {};
        L.forEach(function (l) { porStatus[l._status] = (porStatus[l._status] || 0) + 1; });
        const status = Object.keys(porStatus).sort(function (a, b) { return porStatus[b] - porStatus[a] || a.localeCompare(b); });

        const vinculos = VINCULOS.slice();
        L.forEach(function (l) { if (vinculos.indexOf(l._vinculo) < 0) vinculos.push(l._vinculo); });

        const grupos = [
            { titulo: 'Visão geral', cartoes: [
                { grupo: 'todos', valor: '', rotulo: 'Total ativos', qtd: L.length, ativo: !temFiltro(f), tom: 'destaque' },
                { grupo: 'movimento', valor: 'movimento', rotulo: 'Em movimento', qtd: contar(function (l) { return l.em_movimento; }), ativo: f.movimento === 'movimento' },
                { grupo: 'movimento', valor: 'parado', rotulo: 'Parados', qtd: contar(function (l) { return l.parado; }), ativo: f.movimento === 'parado' },
                { grupo: 'atrasados', valor: 'sim', rotulo: 'Posição desatualizada', qtd: contar(function (l) { return l.posicao_atrasada; }), ativo: f.atrasados, tom: 'alerta' }
            ] },
            { titulo: 'Status operacional', cartoes: status.map(function (s) {
                return { grupo: 'status', valor: s, rotulo: s, qtd: porStatus[s], ativo: f.status.indexOf(s) >= 0, cor: corStatus(s) };
            }) },
            { titulo: 'ETA de destino', cartoes: [
                { grupo: 'eta', valor: 'erro_api', rotulo: 'Erro API Atlas', qtd: contar(function (l) { return l.eta_situacao === 'erro_api'; }), ativo: f.eta.indexOf('erro_api') >= 0, tom: 'perigo' },
                { grupo: 'eta', valor: 'sem_sm', rotulo: 'Sem SM', qtd: contar(function (l) { return l.eta_situacao === 'sem_sm'; }), ativo: f.eta.indexOf('sem_sm') >= 0 }
            ] },
            { titulo: 'Vínculo', cartoes: vinculos.map(function (v) {
                return { grupo: 'vinculo', valor: v, rotulo: v.charAt(0) + v.slice(1).toLowerCase(), qtd: contar(function (l) { return l._vinculo === v; }), ativo: f.vinculo.indexOf(v) >= 0 };
            }) }
        ];

        $('kpis').innerHTML = grupos.map(function (g) {
            return '<div class="kpi-grupo"><span class="kpi-grupo-titulo">' + esc(g.titulo) + '</span>' +
                   '<div class="kpi-linha">' + g.cartoes.map(cartaoKpi).join('') + '</div></div>';
        }).join('');
    }

    function renderFiltrosAtivos(qtdVisiveis) {
        const f = estado.filtros;
        const chips = [];
        const chip = function (grupo, valor, texto) {
            chips.push('<button type="button" class="chip" data-grupo="' + esc(grupo) + '" data-valor="' + esc(valor) + '" ' +
                       'aria-label="Remover filtro ' + esc(texto) + '">' + esc(texto) + ' <span aria-hidden="true">×</span></button>');
        };
        f.status.forEach(function (s) { chip('status', s, 'Status: ' + s); });
        f.vinculo.forEach(function (v) { chip('vinculo', v, 'Vínculo: ' + v); });
        f.eta.forEach(function (e) { chip('eta', e, e === 'erro_api' ? 'Erro API Atlas' : 'Sem SM'); });
        if (f.movimento) chip('movimento', f.movimento, f.movimento === 'parado' ? 'Parados' : 'Em movimento');
        if (f.atrasados) chip('atrasados', 'sim', 'Posição desatualizada');

        $('filtros-ativos').innerHTML = chips.join('');
        $('btn-limpar').hidden = !temFiltro(f);
        $('contagem').textContent = temFiltro(f)
            ? qtdVisiveis + ' de ' + estado.linhas.length + ' veículos'
            : estado.linhas.length + ' veículos';
    }

    function linhaTabela(l) {
        const classes = [];
        if (l.posicao_atrasada) classes.push('linha-atrasada');
        if (l.placa === estado.selecionada) classes.push('selecionada');
        const vel = velocidade(l);
        const sm = l.codigo_sm ? 'SM ' + l.codigo_sm : 'sem SM';
        const frota = l.frota_cavalo ? ' · ' + l.frota_cavalo : '';
        const vinculo = l._vinculo === SEM_VINCULO ? '<span class="vazio">—</span>'
            : '<span class="tag tag-vinculo">' + esc(l._vinculo) + '</span>';

        return '<tr data-placa="' + esc(l.placa) + '" tabindex="0" class="' + classes.join(' ') + '">' +
            '<td data-rotulo="Placa" class="col-placa"><strong>' + esc(placaVisivel(l)) + '</strong><small>' + esc(sm + frota) + '</small></td>' +
            '<td data-rotulo="Carreta" class="col-secundaria">' + ou(l.placa_carreta) + '</td>' +
            '<td data-rotulo="Motorista" class="col-motorista">' + ou(l.motorista_nome) + '</td>' +
            '<td data-rotulo="Vínculo" class="col-secundaria">' + vinculo + '</td>' +
            '<td data-rotulo="Status" class="col-status">' + badgeStatus(l._status) + '</td>' +
            '<td data-rotulo="Macro" class="col-secundaria">' + ou(l.macro_vigente) + '</td>' +
            '<td data-rotulo="km/h" class="num' + (vel === 0 ? ' parado' : '') + '">' + (vel === null ? '<span class="vazio">—</span>' : vel) + '</td>' +
            '<td data-rotulo="Cidade/UF">' + ou(l.cidade_uf) + '</td>' +
            '<td data-rotulo="Localização" class="col-secundaria col-local">' + ou(l.localizacao_atual) + '</td>' +
            '<td data-rotulo="Origem → Destino" class="col-rota">' + ou(l.origem_nome) + ' <span class="seta">→</span> ' + ou(l.destino_nome) + '</td>' +
            '<td data-rotulo="ETA destino">' + textoEta(l) + '</td>' +
            '<td data-rotulo="Última posição" class="col-posicao"><span class="idade">' + esc(idade(l._min)) + '</span>' +
                (l.data_ultima_posicao ? '<small>' + esc(diaHora(l.data_ultima_posicao)) + '</small>' : '') + '</td>' +
            '</tr>';
    }

    function renderTabela(visiveis) {
        const rolagem = $('tabela-rolagem');
        const topo = rolagem.scrollTop;
        $('tabela-corpo').innerHTML = visiveis.map(linhaTabela).join('');
        $('tabela-vazia').hidden = visiveis.length > 0;
        rolagem.scrollTop = topo;

        document.querySelectorAll('#tabela th[data-col]').forEach(function (th) {
            const col = th.getAttribute('data-col');
            th.setAttribute('aria-sort', col === estado.ordem.col ? (estado.ordem.dir === 'asc' ? 'ascending' : 'descending') : 'none');
        });
    }

    function renderLegenda(visiveis) {
        const porStatus = {};
        visiveis.forEach(function (l) { if (l.latitude !== null) porStatus[l._status] = (porStatus[l._status] || 0) + 1; });
        const itens = Object.keys(porStatus).sort().map(function (s) {
            return '<span class="legenda-item"><span class="legenda-ponto" style="--cor:' + corStatus(s) + '"></span>' +
                   esc(s) + ' <b>' + porStatus[s] + '</b></span>';
        });
        itens.push('<span class="legenda-item"><span class="legenda-ponto legenda-atrasado"></span>Posição desatualizada</span>');
        const semPosicao = visiveis.filter(function (l) { return l.latitude === null; }).length;
        if (semPosicao) itens.push('<span class="legenda-item legenda-sem">' + semPosicao + ' sem posição</span>');
        $('legenda').innerHTML = itens.join('');
    }


    // ----------------------------------------------------------------------
    // Mapa
    // ----------------------------------------------------------------------

    function iniciarMapa() {
        if (!window.L) {
            $('mapa').innerHTML = '<p class="mapa-erro">Não foi possível carregar o mapa.</p>';
            return;
        }
        mapa = L.map('mapa', { zoomControl: true, worldCopyJump: true }).setView([-22.9, -46.6], 6);
        L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', {
            maxZoom: 19,
            attribution: '&copy; <a href="https://www.openstreetmap.org/copyright" target="_blank" rel="noopener">OpenStreetMap</a>'
        }).addTo(mapa);

        grupo = L.markerClusterGroup({
            showCoverageOnHover: false,
            maxClusterRadius: 45,
            spiderfyOnMaxZoom: true,
            disableClusteringAtZoom: 15,
            iconCreateFunction: function (cluster) {
                const n = cluster.getChildCount();
                const tam = n < 10 ? 34 : n < 50 ? 40 : 46;
                return L.divIcon({ html: '<span>' + n + '</span>', className: 'agrupado', iconSize: [tam, tam] });
            }
        });
        mapa.addLayer(grupo);

        // Botão "ver todos": enquadra os veículos filtrados
        const Enquadrar = L.Control.extend({
            options: { position: 'topleft' },
            onAdd: function () {
                const b = L.DomUtil.create('button', 'mapa-botao');
                b.type = 'button';
                b.title = 'Enquadrar os veículos filtrados';
                b.setAttribute('aria-label', 'Enquadrar os veículos filtrados');
                b.innerHTML = '<svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><path d="M4 9V4h5M20 9V4h-5M4 15v5h5M20 15v5h-5"/></svg>';
                L.DomEvent.disableClickPropagation(b);
                L.DomEvent.on(b, 'click', enquadrar);
                return b;
            }
        });
        mapa.addControl(new Enquadrar());

        mapa.on('popupopen', function (e) {
            const origem = e.popup && e.popup._source;
            estado.popupAberto = origem && origem._placa ? origem._placa : null;
        });
        mapa.on('popupclose', function () { estado.popupAberto = null; });
    }

    function enquadrar() {
        if (!mapa || !grupo || !grupo.getLayers().length) return;
        mapa.fitBounds(grupo.getBounds(), { padding: [30, 30], maxZoom: 12 });
    }

    function popupHtml(l) {
        const vel = velocidade(l);
        return '<div class="popup">' +
            '<div class="popup-topo"><strong>' + esc(placaVisivel(l)) + '</strong>' + badgeStatus(l._status) + '</div>' +
            '<dl>' +
            '<dt>Motorista</dt><dd>' + ou(l.motorista_nome) + '</dd>' +
            '<dt>Macro</dt><dd>' + ou(l.macro_vigente) + '</dd>' +
            '<dt>Velocidade</dt><dd>' + (vel === null ? '—' : vel + ' km/h') + '</dd>' +
            '<dt>Cidade</dt><dd>' + ou(l.cidade_uf) + '</dd>' +
            '<dt>Posição</dt><dd' + (l.posicao_atrasada ? ' class="texto-alerta"' : '') + '>' +
                esc(diaHora(l.data_ultima_posicao)) + ' (' + esc(idade(l._min)) + ')</dd>' +
            '</dl></div>';
    }

    function icone(l) {
        let classe = 'marcador';
        if (l.posicao_atrasada) classe += ' marcador-atrasado';
        if (l.parado) classe += ' marcador-parado';
        if (l.placa === estado.selecionada) classe += ' marcador-selecionado';
        return L.divIcon({
            className: classe,
            html: '<span style="--cor:' + corStatus(l._status) + '"></span>',
            iconSize: [20, 20],
            iconAnchor: [10, 10],
            popupAnchor: [0, -10]
        });
    }

    function renderMapa(visiveis) {
        if (!mapa) return;
        const reabrir = estado.popupAberto;
        grupo.clearLayers();
        estado.marcadores.clear();

        const novos = [];
        visiveis.forEach(function (l) {
            if (l.latitude === null || l.longitude === null) return;
            const m = L.marker([l.latitude, l.longitude], {
                icon: icone(l),
                title: placaVisivel(l) + ' · ' + l._status,
                alt: placaVisivel(l),
                riseOnHover: true
            });
            m._placa = l.placa;
            m.bindPopup(function () { return popupHtml(l); }, { maxWidth: 300, autoPanPadding: [20, 20] });
            m.on('click', function () { selecionar(l.placa, 'mapa'); });
            novos.push(m);
            estado.marcadores.set(l.placa, m);
        });
        grupo.addLayers(novos);

        if (estado.primeiraCarga && novos.length) enquadrar();

        // Reabre o popup que estava aberto, sem mexer no zoom.
        const m = reabrir && estado.marcadores.get(reabrir);
        if (m && grupo.getVisibleParent(m) === m) m.openPopup();
    }


    // ----------------------------------------------------------------------
    // Interação
    // ----------------------------------------------------------------------

    function selecionar(placa, origem) {
        estado.selecionada = placa;

        document.querySelectorAll('#tabela-corpo tr.selecionada').forEach(function (tr) { tr.classList.remove('selecionada'); });
        const linha = document.querySelector('#tabela-corpo tr[data-placa="' + cssEscape(placa) + '"]');
        if (linha) linha.classList.add('selecionada');

        document.querySelectorAll('.marcador-selecionado').forEach(function (el) { el.classList.remove('marcador-selecionado'); });
        const m = estado.marcadores.get(placa);
        if (m && m._icon) m._icon.classList.add('marcador-selecionado');

        if (origem === 'mapa' && linha) {
            const rolagem = $('tabela-rolagem');
            if (rolagem.scrollHeight > rolagem.clientHeight + 4) {
                rolagem.scrollTop = linha.offsetTop - rolagem.clientHeight / 2 + linha.offsetHeight / 2;
            }
        }

        if (origem === 'tabela') {
            if (!m || !mapa) {
                mostrarAviso('Este veículo está sem posição no momento.', 4000);
                return;
            }
            const caixa = mapa.getContainer().getBoundingClientRect();
            if (caixa.top < 0 || caixa.bottom > window.innerHeight) {
                mapa.getContainer().scrollIntoView({ behavior: 'smooth', block: 'center' });
            }
            grupo.zoomToShowLayer(m, function () {
                mapa.panTo(m.getLatLng());
                m.openPopup();
                if (m._icon) m._icon.classList.add('marcador-selecionado');
            });
        }
    }

    function cssEscape(texto) {
        return window.CSS && CSS.escape ? CSS.escape(texto) : String(texto).replace(/["\\]/g, '\\$&');
    }

    function alternarFiltro(grupoFiltro, valor) {
        const f = estado.filtros;
        if (grupoFiltro === 'todos') {
            limparFiltros();
            return;
        }
        if (grupoFiltro === 'status' || grupoFiltro === 'vinculo' || grupoFiltro === 'eta') {
            const i = f[grupoFiltro].indexOf(valor);
            if (i >= 0) f[grupoFiltro].splice(i, 1); else f[grupoFiltro].push(valor);
        } else if (grupoFiltro === 'movimento') {
            f.movimento = f.movimento === valor ? null : valor;
        } else if (grupoFiltro === 'atrasados') {
            f.atrasados = !f.atrasados;
        }
        filtrosMudaram();
    }

    function limparFiltros() {
        estado.filtros = normalizarFiltros({});
        $('busca').value = '';
        filtrosMudaram();
    }

    function filtrosMudaram() {
        app.salvarPreferencia(CHAVE_FILTROS, estado.filtros);
        renderTudo();
    }

    let avisoTimer = null;
    function mostrarAviso(texto, msParaSumir) {
        const el = $('aviso');
        el.textContent = texto;
        el.hidden = false;
        clearTimeout(avisoTimer);
        if (msParaSumir) avisoTimer = setTimeout(esconderAviso, msParaSumir);
    }
    function esconderAviso() { $('aviso').hidden = true; }

    function alternarTv(ligar) {
        document.body.classList.toggle('modo-tv', ligar);
        $('btn-tv').setAttribute('aria-pressed', ligar ? 'true' : 'false');
        app.salvarPreferencia(CHAVE_TV, ligar);

        const raiz = document.documentElement;
        if (ligar && raiz.requestFullscreen && !document.fullscreenElement) {
            raiz.requestFullscreen().then(function () { estado.tvTelaCheia = true; }).catch(function () {});
        } else if (!ligar && document.fullscreenElement && document.exitFullscreen) {
            estado.tvTelaCheia = false;
            document.exitFullscreen().catch(function () {});
        }
        setTimeout(function () { if (mapa) mapa.invalidateSize(); }, 300);
    }

    function ligarEventos() {
        $('kpis').addEventListener('click', function (e) {
            const b = e.target.closest('button.kpi');
            if (b) alternarFiltro(b.getAttribute('data-grupo'), b.getAttribute('data-valor'));
        });
        $('filtros-ativos').addEventListener('click', function (e) {
            const b = e.target.closest('button.chip');
            if (b) alternarFiltro(b.getAttribute('data-grupo'), b.getAttribute('data-valor'));
        });
        $('btn-limpar').addEventListener('click', limparFiltros);

        let espera = null;
        $('busca').addEventListener('input', function (e) {
            clearTimeout(espera);
            espera = setTimeout(function () {
                estado.filtros.busca = e.target.value;
                filtrosMudaram();
            }, 150);
        });

        document.querySelector('#tabela thead').addEventListener('click', function (e) {
            const th = e.target.closest('th[data-col]');
            if (!th) return;
            const col = th.getAttribute('data-col');
            estado.ordem = { col: col, dir: estado.ordem.col === col && estado.ordem.dir === 'asc' ? 'desc' : 'asc' };
            app.salvarPreferencia(CHAVE_ORDEM, estado.ordem);
            renderTudo();
        });

        const corpo = $('tabela-corpo');
        corpo.addEventListener('click', function (e) {
            const tr = e.target.closest('tr[data-placa]');
            if (tr) selecionar(tr.getAttribute('data-placa'), 'tabela');
        });
        corpo.addEventListener('keydown', function (e) {
            if (e.key !== 'Enter' && e.key !== ' ') return;
            const tr = e.target.closest('tr[data-placa]');
            if (!tr) return;
            e.preventDefault();
            selecionar(tr.getAttribute('data-placa'), 'tabela');
        });

        $('btn-tv').addEventListener('click', function () {
            alternarTv(!document.body.classList.contains('modo-tv'));
        });
        document.addEventListener('fullscreenchange', function () {
            if (!document.fullscreenElement && estado.tvTelaCheia) {
                estado.tvTelaCheia = false;
                alternarTv(false);
            }
        });

        $('btn-tema').addEventListener('click', function () {
            const novo = app.temaEfetivo() === 'escuro' ? 'claro' : 'escuro';
            app.aplicarTema(novo);
            app.salvarPreferencia('torre.tema', novo);
        });

        $('btn-sair').addEventListener('click', async function () {
            await app.sair();
            window.location.replace('login.html?motivo=saiu');
        });

        sb.auth.onAuthStateChange(function (evento) {
            if (evento === 'SIGNED_OUT') window.location.replace('login.html?motivo=saiu');
        });

        // Atualiza a cada 60 s, só com a aba visível; ao voltar para a aba, atualiza se passou do tempo.
        setInterval(function () { if (!document.hidden) carregar(); }, INTERVALO_MS);
        document.addEventListener('visibilitychange', function () {
            if (!document.hidden && Date.now() - estado.ultimaCarga >= INTERVALO_MS) carregar();
        });
    }


    // ----------------------------------------------------------------------
    // Início
    // ----------------------------------------------------------------------

    async function iniciar() {
        const ctx = await app.exigirOperador();
        $('usuario-nome').textContent = ctx.operador.nome;
        $('busca').value = estado.filtros.busca;

        iniciarMapa();
        ligarEventos();
        if (app.lerPreferencia(CHAVE_TV, false) === true) alternarTv(true);
        await carregar();
    }

    iniciar();
})();
