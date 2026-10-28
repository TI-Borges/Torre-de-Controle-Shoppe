-- =============================================================================
-- Torre de Controle Shopee - Apagar os dados de EXEMPLO
-- =============================================================================
-- Rodar depois de conferir que a sincronização real com o Atlas está funcionando.
-- Apaga só o que veio de supabase/sql/dados_exemplo.sql:
--   veículos com "_exemplo" no bruto (placas TSTE...), as posições e paradas deles e o
--   registro de sincronização marcado como fonte 'exemplo'.
-- Não toca em nenhum dado real, e só mexe em tabelas do schema torre.
-- =============================================================================

begin;

delete from torre.posicoes      where placa in (select placa from torre.veiculos_atual where bruto ? '_exemplo');
delete from torre.paradas_atual where placa in (select placa from torre.veiculos_atual where bruto ? '_exemplo');
delete from torre.veiculos_atual where bruto ? '_exemplo';
delete from torre.sincronizacao where fonte = 'exemplo';

commit;

-- Conferir (esperado: 0 | 0 | 0):
--   select (select count(*) from torre.veiculos_atual where bruto ? '_exemplo') as veiculos_exemplo,
--          (select count(*) from torre.posicoes where placa like 'TSTE%')         as posicoes_exemplo,
--          (select count(*) from torre.sincronizacao where fonte = 'exemplo')     as sincronizacoes_exemplo;
