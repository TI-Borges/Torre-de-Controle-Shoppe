// Gera supabase/sql/dados_exemplo.sql a partir de testes/amostra_atlas.json.
// Uso: node testes/gerar_dados_exemplo.mjs
// O teste testes/sql.test.mjs confere que o arquivo gerado está em dia com a amostra.
import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const RAIZ = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

// "Agora" usado para montar as datas da amostra (horário de Brasília).
export const REFERENCIA_AMOSTRA = '2026-10-28 12:00:00-03';

export function montarDadosExemplo() {
  const amostra = JSON.parse(readFileSync(path.join(RAIZ, 'testes', 'amostra_atlas.json'), 'utf8'));
  const json = JSON.stringify(amostra, null, 1);
  if (json.includes('$amostra$')) throw new Error('a amostra não pode conter $amostra$');

  return `-- =============================================================================
-- Torre de Controle Shopee - Dados de EXEMPLO (para ver o painel antes da API real)
-- =============================================================================
-- ARQUIVO GERADO por testes/gerar_dados_exemplo.mjs a partir de
-- testes/amostra_atlas.json. Não edite à mão.
--
-- São 30 veículos inventados (placas TSTE..., motoristas "Motorista Exemplo NN").
-- Cada item tem "_exemplo": true no bruto, o que permite apagar tudo depois com
-- supabase/sql/apagar_dados_exemplo.sql. Os CPFs da amostra são falsos e, de
-- qualquer forma, a função aplicar_atlas os remove antes de gravar.
--
-- As datas da amostra foram montadas com "agora" = ${REFERENCIA_AMOSTRA}.
-- Depois de carregar, este script desloca todas as datas para o "agora" real,
-- para o painel mostrar posições recentes. Rode de novo para "atualizar" o exemplo.
--
-- Recusa rodar se já houver dados reais (veículos sem a marca "_exemplo").
-- Só mexe em tabelas do schema torre (rodar depois do passo 01).
-- =============================================================================

begin;

do $$
begin
  if exists (select 1 from torre.veiculos_atual where not (bruto ? '_exemplo')) then
    raise exception 'Já existem dados reais do Atlas: os dados de exemplo não foram carregados.';
  end if;
end $$;

-- Tira o exemplo anterior, se houver, para recarregar do zero.
delete from torre.posicoes where placa in (select placa from torre.veiculos_atual where bruto ? '_exemplo');
delete from torre.paradas_atual where placa in (select placa from torre.veiculos_atual where bruto ? '_exemplo');
delete from torre.veiculos_atual where bruto ? '_exemplo';

select torre.aplicar_atlas($amostra$
${json}
$amostra$::jsonb);

-- Desloca as datas para o "agora" real.
update torre.veiculos_atual
   set data_cadastro_sm     = data_cadastro_sm     + (now() - '${REFERENCIA_AMOSTRA}'::timestamptz),
       data_ultima_posicao  = data_ultima_posicao  + (now() - '${REFERENCIA_AMOSTRA}'::timestamptz),
       origem_eta_original  = origem_eta_original  + (now() - '${REFERENCIA_AMOSTRA}'::timestamptz),
       origem_eta_real      = origem_eta_real      + (now() - '${REFERENCIA_AMOSTRA}'::timestamptz),
       origem_entrada       = origem_entrada       + (now() - '${REFERENCIA_AMOSTRA}'::timestamptz),
       origem_saida         = origem_saida         + (now() - '${REFERENCIA_AMOSTRA}'::timestamptz),
       origem_entrada_real  = origem_entrada_real  + (now() - '${REFERENCIA_AMOSTRA}'::timestamptz),
       origem_saida_real    = origem_saida_real    + (now() - '${REFERENCIA_AMOSTRA}'::timestamptz),
       destino_eta_original = destino_eta_original + (now() - '${REFERENCIA_AMOSTRA}'::timestamptz),
       destino_eta_real     = destino_eta_real     + (now() - '${REFERENCIA_AMOSTRA}'::timestamptz),
       destino_entrada      = destino_entrada      + (now() - '${REFERENCIA_AMOSTRA}'::timestamptz),
       destino_saida        = destino_saida        + (now() - '${REFERENCIA_AMOSTRA}'::timestamptz),
       destino_entrada_real = destino_entrada_real + (now() - '${REFERENCIA_AMOSTRA}'::timestamptz),
       destino_saida_real   = destino_saida_real   + (now() - '${REFERENCIA_AMOSTRA}'::timestamptz),
       previsao_inicio      = previsao_inicio      + (now() - '${REFERENCIA_AMOSTRA}'::timestamptz),
       previsao_fim         = previsao_fim         + (now() - '${REFERENCIA_AMOSTRA}'::timestamptz),
       inicio_real          = inicio_real          + (now() - '${REFERENCIA_AMOSTRA}'::timestamptz)
 where bruto ? '_exemplo';

update torre.paradas_atual
   set eta_original = eta_original + (now() - '${REFERENCIA_AMOSTRA}'::timestamptz),
       eta_real     = eta_real     + (now() - '${REFERENCIA_AMOSTRA}'::timestamptz),
       entrada      = entrada      + (now() - '${REFERENCIA_AMOSTRA}'::timestamptz),
       saida        = saida        + (now() - '${REFERENCIA_AMOSTRA}'::timestamptz),
       entrada_real = entrada_real + (now() - '${REFERENCIA_AMOSTRA}'::timestamptz),
       saida_real   = saida_real   + (now() - '${REFERENCIA_AMOSTRA}'::timestamptz)
 where placa in (select placa from torre.veiculos_atual where bruto ? '_exemplo');

-- Histórico: refaz com as datas já deslocadas.
delete from torre.posicoes where placa in (select placa from torre.veiculos_atual where bruto ? '_exemplo');
insert into torre.posicoes (placa, latitude, longitude, velocidade, macro, data_posicao)
select placa, latitude, longitude, velocidade, macro_vigente, data_ultima_posicao
  from torre.veiculos_atual
 where bruto ? '_exemplo' and latitude is not null and data_ultima_posicao is not null
on conflict do nothing;

-- Marca o registro de sincronização como exemplo.
update torre.sincronizacao
   set fonte = 'exemplo'
 where id = (select max(id) from torre.sincronizacao);

commit;

-- Conferir (esperado: 29 veículos ativos; 1 item sem placa e sem SM foi ignorado):
--   select count(*) as veiculos, count(*) filter (where posicao_atrasada) as atrasados from torre.v_painel;
--   select id, fonte, recebidos, gravados, sem_placa, erro from torre.sincronizacao order by id desc limit 1;
`;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  writeFileSync(path.join(RAIZ, 'supabase', 'sql', 'dados_exemplo.sql'), montarDadosExemplo());
  console.log('supabase/sql/dados_exemplo.sql gerado.');
}
