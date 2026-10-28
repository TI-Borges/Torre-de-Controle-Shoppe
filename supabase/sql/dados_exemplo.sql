-- =============================================================================
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
-- As datas da amostra foram montadas com "agora" = 2026-10-28 12:00:00-03.
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
[
 {
  "_exemplo": true,
  "nome_cliente": "SHOPEE (EXEMPLO)",
  "operacao": "SHOPEE - LINE HAUL",
  "codigo_sm": "9900001",
  "status_sm": "EM ANDAMENTO",
  "status_operacional": "Carregando",
  "data_cadastro_sm": "2026-10-28T03:00:00-03:00",
  "latitude": -23.3556,
  "longitude": -46.877,
  "data_ultima_posicao": "2026-10-28T11:53:00-03:00",
  "velocidade": 0,
  "macro_vigente": "INICIO CARREGAMENTO",
  "cidade_uf": "Cajamar/SP",
  "localizacao_atual": "CD Cajamar - Rod. Anhanguera",
  "rota": {
   "codigo": "R101",
   "descricao": "Cajamar/SP x CD Betim",
   "km_total": 187,
   "tempo_total": "4:30"
  },
  "origem": {
   "nome": "CD Cajamar",
   "eta_original": "2026-10-28T05:00:00-03:00",
   "eta_real": "2026-10-28T05:20:00-03:00",
   "entrada": "2026-10-28T04:00:00-03:00",
   "saida": "2026-10-28T05:00:00-03:00",
   "entrada_real": "2026-10-28T04:10:00-03:00",
   "saida_real": "2026-10-28T05:15:00-03:00"
  },
  "destino": {
   "nome": "CD Betim",
   "eta_original": "2026-10-28T14:37:00-03:00",
   "eta_real": "2026-10-28T15:07:00-03:00",
   "entrada": "2026-10-28T15:37:00-03:00",
   "saida": "2026-10-28T18:07:00-03:00",
   "entrada_real": null,
   "saida_real": null
  },
  "motoristas": [
   {
    "nome": "Motorista Exemplo 01",
    "cpf": "000.000.001-00",
    "vinculo": "TERCEIRO"
   }
  ],
  "placas": [
   {
    "placa": "TSTE-001",
    "frota": null,
    "vinculo": "TERCEIRO",
    "tipo": "CAVALO"
   },
   {
    "placa": "TSTC-001",
    "frota": null,
    "vinculo": "TERCEIRO",
    "tipo": "CARRETA"
   }
  ],
  "paradas": [],
  "previsao_inicio": "2026-10-28T05:00:00-03:00",
  "previsao_fim": "2026-10-28T15:07:00-03:00",
  "inicio_real": "2026-10-28T05:15:00-03:00"
 },
 {
  "_exemplo": true,
  "nome_cliente": "SHOPEE (EXEMPLO)",
  "operacao": "SHOPEE - LINE HAUL",
  "codigo_sm": "9900002",
  "status_sm": "EM ANDAMENTO",
  "status_operacional": "Em Descarga",
  "data_cadastro_sm": "2026-10-28T05:00:00Z",
  "latitude": -23.3561,
  "longitude": -46.8782,
  "data_ultima_posicao": "2026-10-28T14:48:00Z",
  "velocidade": 0,
  "macro_vigente": "INICIO DESCARGA",
  "cidade_uf": "Cajamar/SP",
  "localizacao_atual": "CD Cajamar - Pátio",
  "rota": {
   "codigo": "R102",
   "descricao": "Cajamar/SP x CD Curitiba",
   "km_total": 224,
   "tempo_total": "5:30"
  },
  "origem": {
   "nome": "CD Cajamar",
   "eta_original": "2026-10-28T07:00:00Z",
   "eta_real": "2026-10-28T07:20:00Z",
   "entrada": "2026-10-28T06:00:00Z",
   "saida": "2026-10-28T07:00:00Z",
   "entrada_real": "2026-10-28T06:10:00Z",
   "saida_real": "2026-10-28T07:15:00Z"
  },
  "destino": {
   "nome": "CD Curitiba",
   "eta_original": "2026-10-28T18:44:00Z",
   "eta_real": "2026-10-28T19:14:00Z",
   "entrada": "2026-10-28T19:44:00Z",
   "saida": "2026-10-28T22:14:00Z",
   "entrada_real": null,
   "saida_real": null
  },
  "motoristas": [
   {
    "nome": "Motorista Exemplo 02",
    "cpf": "000.000.002-00",
    "vinculo": "AGREGADO"
   }
  ],
  "placas": [
   {
    "placa": "TSTE-002",
    "frota": null,
    "vinculo": "AGREGADO",
    "tipo": "CAVALO"
   },
   {
    "placa": "TSTC-002",
    "frota": null,
    "vinculo": "AGREGADO",
    "tipo": "CARRETA"
   }
  ],
  "paradas": [],
  "previsao_inicio": "2026-10-28T07:00:00Z",
  "previsao_fim": "2026-10-28T19:14:00Z",
  "inicio_real": "2026-10-28T07:15:00Z"
 },
 {
  "_exemplo": true,
  "nome_cliente": "SHOPEE (EXEMPLO)",
  "operacao": "SHOPEE - LINE HAUL",
  "codigo_sm": "9900003",
  "status_sm": "PROGRAMADA",
  "status_operacional": "Sem Viagem",
  "data_cadastro_sm": "2026-10-28T01:00:00",
  "latitude": -23.3549,
  "longitude": -46.8761,
  "data_ultima_posicao": "2026-10-28T11:56:00",
  "velocidade": 0,
  "macro_vigente": "PERNOITE",
  "cidade_uf": "Cajamar/SP",
  "localizacao_atual": "CD Cajamar - Doca 3",
  "rota": {
   "codigo": "R103",
   "descricao": "Cajamar/SP x CD Campinas",
   "km_total": 261,
   "tempo_total": "6:30"
  },
  "origem": {
   "nome": "CD Cajamar",
   "eta_original": "2026-10-28T03:00:00",
   "eta_real": "2026-10-28T03:20:00",
   "entrada": "2026-10-28T02:00:00",
   "saida": "2026-10-28T03:00:00",
   "entrada_real": "2026-10-28T02:10:00",
   "saida_real": "2026-10-28T03:15:00"
  },
  "destino": {
   "nome": "CD Campinas",
   "eta_original": "2026-10-28T16:51:00",
   "eta_real": "2026-10-28T17:21:00",
   "entrada": "2026-10-28T17:51:00",
   "saida": "2026-10-28T20:21:00",
   "entrada_real": null,
   "saida_real": null
  },
  "motoristas": [
   {
    "nome": "Motorista Exemplo 03",
    "cpf": "000.000.003-00",
    "vinculo": "FROTA"
   }
  ],
  "placas": [
   {
    "placa": "TSTE-003",
    "frota": "F103",
    "vinculo": "FROTA",
    "tipo": "CAVALO"
   },
   {
    "placa": "TSTC-003",
    "frota": null,
    "vinculo": "FROTA",
    "tipo": "CARRETA"
   }
  ],
  "paradas": [
   {
    "nome": "Posto de apoio",
    "sequencia": 1,
    "eta_original": "2026-10-28T05:00:00",
    "eta_real": "2026-10-28T05:10:00",
    "entrada": null,
    "saida": null,
    "entrada_real": "2026-10-28T05:05:00",
    "saida_real": "2026-10-28T05:40:00"
   },
   {
    "nome": "CD Campinas",
    "sequencia": 2,
    "eta_original": "2026-10-28T16:51:00",
    "eta_real": "2026-10-28T17:21:00",
    "entrada": null,
    "saida": null,
    "entrada_real": null,
    "saida_real": null
   }
  ],
  "previsao_inicio": "2026-10-28T03:00:00",
  "previsao_fim": "2026-10-28T17:21:00",
  "inicio_real": "2026-10-28T03:15:00"
 },
 {
  "_exemplo": true,
  "nome_cliente": "SHOPEE (EXEMPLO)",
  "operacao": "SHOPEE - TRANSFERENCIA",
  "codigo_sm": 0,
  "status_sm": null,
  "status_operacional": "Em Viagem Carregado",
  "data_cadastro_sm": null,
  "latitude": -23.1857,
  "longitude": -46.8978,
  "data_ultima_posicao": "28/10/2026 11:51",
  "velocidade": 46,
  "macro_vigente": "INICIO DE VIAGEM",
  "cidade_uf": "Jundiaí/SP",
  "localizacao_atual": "Rod. Anhanguera km 58",
  "rota": null,
  "origem": null,
  "destino": null,
  "motoristas": [
   {
    "nome": "Motorista Exemplo 04",
    "cpf": "000.000.004-00",
    "vinculo": "TERCEIRO"
   }
  ],
  "placas": [
   {
    "placa": "TSTE-004",
    "frota": null,
    "vinculo": "TERCEIRO",
    "tipo": "CAVALO"
   },
   {
    "placa": "TSTC-004",
    "frota": null,
    "vinculo": "FROTA",
    "tipo": "CARRETA"
   }
  ],
  "paradas": [],
  "previsao_inicio": null,
  "previsao_fim": null,
  "inicio_real": null
 },
 {
  "_exemplo": true,
  "nome_cliente": "SHOPEE (EXEMPLO)",
  "operacao": "SHOPEE - LINE HAUL",
  "codigo_sm": "9900005",
  "status_sm": "EM ANDAMENTO",
  "status_operacional": "Em Viagem Vazio",
  "data_cadastro_sm": "2026-10-27T23:00:00-03:00",
  "latitude": -22.9056,
  "longitude": -47.0608,
  "data_ultima_posicao": "2026-10-28T11:46:00-03:00",
  "velocidade": 59,
  "macro_vigente": "RETORNO VAZIO",
  "cidade_uf": "Campinas/SP",
  "localizacao_atual": "Rod. Dom Pedro I km 140",
  "rota": {
   "codigo": "R105",
   "descricao": "Cajamar/SP x CD Duque de Caxias",
   "km_total": 335,
   "tempo_total": "8:30"
  },
  "origem": {
   "nome": "CD Cajamar",
   "eta_original": "2026-10-28T01:00:00-03:00",
   "eta_real": "2026-10-28T01:20:00-03:00",
   "entrada": "2026-10-28T00:00:00-03:00",
   "saida": "2026-10-28T01:00:00-03:00",
   "entrada_real": "2026-10-28T00:10:00-03:00",
   "saida_real": "2026-10-28T01:15:00-03:00"
  },
  "destino": {
   "nome": "CD Duque de Caxias",
   "eta_original": "2026-10-28T19:05:00-03:00",
   "eta_real": null,
   "entrada": "2026-10-28T20:05:00-03:00",
   "saida": "2026-10-28T22:35:00-03:00",
   "entrada_real": null,
   "saida_real": null
  },
  "motoristas": [
   {
    "nome": "Motorista Exemplo 05",
    "cpf": "000.000.005-00",
    "vinculo": "AGREGADO"
   }
  ],
  "placas": [
   {
    "placa": "TSTE-005",
    "frota": null,
    "vinculo": "AGREGADO",
    "tipo": "CAVALO"
   }
  ],
  "paradas": [],
  "previsao_inicio": "2026-10-28T01:00:00-03:00",
  "previsao_fim": "2026-10-28T19:35:00-03:00",
  "inicio_real": "2026-10-28T01:15:00-03:00"
 },
 {
  "_exemplo": true,
  "nome_cliente": "SHOPEE (EXEMPLO)",
  "operacao": "SHOPEE - LINE HAUL",
  "codigo_sm": "9900006",
  "status_sm": "EM ANDAMENTO",
  "status_operacional": "Em Viagem Carregado",
  "data_cadastro_sm": "2026-10-28T01:00:00Z",
  "latitude": -23.0856,
  "longitude": -46.9504,
  "data_ultima_posicao": "2026-10-28T14:54:00Z",
  "velocidade": 72,
  "macro_vigente": "INICIO DE VIAGEM",
  "cidade_uf": "Louveira/SP",
  "localizacao_atual": "Rod. Anhanguera km 72",
  "rota": {
   "codigo": "R106",
   "descricao": "Cajamar/SP x CD Betim",
   "km_total": 372,
   "tempo_total": "9:30"
  },
  "origem": {
   "nome": "CD Cajamar",
   "eta_original": "2026-10-28T03:00:00Z",
   "eta_real": "2026-10-28T03:20:00Z",
   "entrada": "2026-10-28T02:00:00Z",
   "saida": "2026-10-28T03:00:00Z",
   "entrada_real": "2026-10-28T02:10:00Z",
   "saida_real": "2026-10-28T03:15:00Z"
  },
  "destino": {
   "nome": "CD Betim",
   "eta_original": "2026-10-28T23:12:00Z",
   "eta_real": "2026-10-28T23:42:00Z",
   "entrada": "2026-10-29T00:12:00Z",
   "saida": "2026-10-29T02:42:00Z",
   "entrada_real": null,
   "saida_real": null
  },
  "motoristas": [
   {
    "nome": "Motorista Exemplo 06",
    "cpf": "000.000.006-00",
    "vinculo": "FROTA"
   }
  ],
  "placas": [
   {
    "placa": "tste 006",
    "frota": null,
    "vinculo": "FROTA",
    "tipo": null
   }
  ],
  "paradas": [
   {
    "nome": "Posto de apoio",
    "sequencia": 1,
    "eta_original": "2026-10-28T05:00:00Z",
    "eta_real": "2026-10-28T05:10:00Z",
    "entrada": null,
    "saida": null,
    "entrada_real": "2026-10-28T05:05:00Z",
    "saida_real": "2026-10-28T05:40:00Z"
   },
   {
    "nome": "CD Betim",
    "sequencia": 2,
    "eta_original": "2026-10-28T23:12:00Z",
    "eta_real": "2026-10-28T23:42:00Z",
    "entrada": null,
    "saida": null,
    "entrada_real": null,
    "saida_real": null
   }
  ],
  "previsao_inicio": "2026-10-28T03:00:00Z",
  "previsao_fim": "2026-10-28T23:42:00Z",
  "inicio_real": "2026-10-28T03:15:00Z"
 },
 {
  "_exemplo": true,
  "nome_cliente": "SHOPEE (EXEMPLO)",
  "operacao": "SHOPEE - LINE HAUL",
  "codigo_sm": "9900007",
  "status_sm": "EM ANDAMENTO",
  "status_operacional": "Carregando",
  "data_cadastro_sm": "2026-10-27T21:00:00",
  "latitude": -23.4628,
  "longitude": -46.5333,
  "data_ultima_posicao": "2026-10-28T11:10:00",
  "velocidade": 0,
  "macro_vigente": "INICIO CARREGAMENTO",
  "cidade_uf": "Guarulhos/SP",
  "localizacao_atual": "Rod. Presidente Dutra km 225",
  "rota": {
   "codigo": "R107",
   "descricao": "Cajamar/SP x CD Curitiba",
   "km_total": 409,
   "tempo_total": "10:30"
  },
  "origem": {
   "nome": "CD Cajamar",
   "eta_original": "2026-10-27T23:00:00",
   "eta_real": "2026-10-27T23:20:00",
   "entrada": "2026-10-27T22:00:00",
   "saida": "2026-10-27T23:00:00",
   "entrada_real": "2026-10-27T22:10:00",
   "saida_real": "2026-10-27T23:15:00"
  },
  "destino": {
   "nome": "CD Curitiba",
   "eta_original": "2026-10-28T21:19:00",
   "eta_real": "2026-10-28T21:49:00",
   "entrada": "2026-10-28T22:19:00",
   "saida": "2026-10-29T00:49:00",
   "entrada_real": null,
   "saida_real": null
  },
  "motoristas": [
   {
    "nome": "Motorista Exemplo 07",
    "cpf": "000.000.007-00",
    "vinculo": "TERCEIRO"
   }
  ],
  "placas": [
   {
    "placa": "TSTE-007",
    "frota": null,
    "vinculo": "TERCEIRO",
    "tipo": "CAVALO"
   },
   {
    "placa": "TSTC-007",
    "frota": null,
    "vinculo": "TERCEIRO",
    "tipo": "CARRETA"
   }
  ],
  "paradas": [],
  "previsao_inicio": "2026-10-27T23:00:00",
  "previsao_fim": "2026-10-28T21:49:00",
  "inicio_real": "2026-10-27T23:15:00"
 },
 {
  "_exemplo": true,
  "nome_cliente": "SHOPEE (EXEMPLO)",
  "operacao": "SHOPEE - TRANSFERENCIA",
  "codigo_sm": "0",
  "status_sm": null,
  "status_operacional": "Em Descarga",
  "data_cadastro_sm": null,
  "latitude": -23.1896,
  "longitude": -45.8841,
  "data_ultima_posicao": "28/10/2026 11:57",
  "velocidade": 0,
  "macro_vigente": "INICIO DESCARGA",
  "cidade_uf": "São José dos Campos/SP",
  "localizacao_atual": "Rod. Presidente Dutra km 150",
  "rota": null,
  "origem": null,
  "destino": null,
  "motoristas": [
   {
    "nome": "Motorista Exemplo 08",
    "cpf": "000.000.008-00",
    "vinculo": "AGREGADO"
   }
  ],
  "placas": [
   {
    "placa": "TSTE-008",
    "frota": null,
    "vinculo": "AGREGADO",
    "tipo": "CAVALO"
   },
   {
    "placa": "TSTC-008",
    "frota": null,
    "vinculo": "FROTA",
    "tipo": "CARRETA"
   }
  ],
  "paradas": [],
  "previsao_inicio": null,
  "previsao_fim": null,
  "inicio_real": null
 },
 {
  "_exemplo": true,
  "nome_cliente": "SHOPEE (EXEMPLO)",
  "operacao": "SHOPEE - LINE HAUL",
  "codigo_sm": "9900009",
  "status_sm": "PROGRAMADA",
  "status_operacional": "Sem Viagem",
  "data_cadastro_sm": "2026-10-27T19:00:00-03:00",
  "latitude": "-22,4705",
  "longitude": "-44,4509",
  "data_ultima_posicao": "2026-10-28T11:52:00-03:00",
  "velocidade": 0,
  "macro_vigente": "PERNOITE",
  "cidade_uf": "Resende/RJ",
  "localizacao_atual": "Rod. Presidente Dutra km 310",
  "rota": {
   "codigo": "R109",
   "descricao": "Cajamar/SP x CD Barueri",
   "km_total": 483,
   "tempo_total": "3:30"
  },
  "origem": {
   "nome": "CD Cajamar",
   "eta_original": "2026-10-27T21:00:00-03:00",
   "eta_real": "2026-10-27T21:20:00-03:00",
   "entrada": "2026-10-27T20:00:00-03:00",
   "saida": "2026-10-27T21:00:00-03:00",
   "entrada_real": "2026-10-27T20:10:00-03:00",
   "saida_real": "2026-10-27T21:15:00-03:00"
  },
  "destino": {
   "nome": "CD Barueri",
   "eta_original": "2026-10-28T13:33:00-03:00",
   "eta_real": "2026-10-28T14:03:00-03:00",
   "entrada": "2026-10-28T14:33:00-03:00",
   "saida": "2026-10-28T17:03:00-03:00",
   "entrada_real": null,
   "saida_real": null
  },
  "motoristas": [
   {
    "nome": "Motorista Exemplo 09",
    "cpf": "000.000.009-00",
    "vinculo": "FROTA"
   }
  ],
  "placas": [
   {
    "placa": "TSTE-009",
    "frota": "F109",
    "vinculo": "FROTA",
    "tipo": "CAVALO"
   },
   {
    "placa": "TSTC-009",
    "frota": null,
    "vinculo": "FROTA",
    "tipo": "CARRETA"
   }
  ],
  "paradas": [
   {
    "nome": "Posto de apoio",
    "sequencia": 1,
    "eta_original": "2026-10-27T23:00:00-03:00",
    "eta_real": "2026-10-27T23:10:00-03:00",
    "entrada": null,
    "saida": null,
    "entrada_real": "2026-10-27T23:05:00-03:00",
    "saida_real": "2026-10-27T23:40:00-03:00"
   },
   {
    "nome": "CD Barueri",
    "sequencia": 2,
    "eta_original": "2026-10-28T13:33:00-03:00",
    "eta_real": "2026-10-28T14:03:00-03:00",
    "entrada": null,
    "saida": null,
    "entrada_real": null,
    "saida_real": null
   }
  ],
  "previsao_inicio": "2026-10-27T21:00:00-03:00",
  "previsao_fim": "2026-10-28T14:03:00-03:00",
  "inicio_real": "2026-10-27T21:15:00-03:00"
 },
 {
  "_exemplo": true,
  "nome_cliente": "SHOPEE (EXEMPLO)",
  "operacao": "SHOPEE - LINE HAUL",
  "codigo_sm": "9900010",
  "status_sm": "EM ANDAMENTO",
  "status_operacional": "Em Viagem Carregado",
  "data_cadastro_sm": "2026-10-28T07:00:00Z",
  "latitude": -22.8382,
  "longitude": -43.281,
  "data_ultima_posicao": "2026-10-28T14:47:00Z",
  "velocidade": 0,
  "macro_vigente": "INICIO DE VIAGEM",
  "cidade_uf": "Rio de Janeiro/RJ",
  "localizacao_atual": "Av. Brasil - Penha",
  "rota": {
   "codigo": "R110",
   "descricao": "Cajamar/SP x CD Duque de Caxias",
   "km_total": 520,
   "tempo_total": "4:30"
  },
  "origem": {
   "nome": "CD Cajamar",
   "eta_original": "2026-10-28T09:00:00Z",
   "eta_real": "2026-10-28T09:20:00Z",
   "entrada": "2026-10-28T08:00:00Z",
   "saida": "2026-10-28T09:00:00Z",
   "entrada_real": "2026-10-28T08:10:00Z",
   "saida_real": "2026-10-28T09:15:00Z"
  },
  "destino": {
   "nome": "CD Duque de Caxias",
   "eta_original": "2026-10-28T17:40:00Z",
   "eta_real": "2026-10-28T18:10:00Z",
   "entrada": "2026-10-28T18:40:00Z",
   "saida": "2026-10-28T21:10:00Z",
   "entrada_real": null,
   "saida_real": null
  },
  "motoristas": [
   {
    "nome": "Motorista Exemplo 10",
    "cpf": "000.000.010-00",
    "vinculo": "TERCEIRO"
   }
  ],
  "placas": [
   {
    "placa": "TSTE-010",
    "frota": null,
    "vinculo": "TERCEIRO",
    "tipo": "CAVALO"
   }
  ],
  "paradas": [],
  "previsao_inicio": "2026-10-28T09:00:00Z",
  "previsao_fim": "2026-10-28T18:10:00Z",
  "inicio_real": "2026-10-28T09:15:00Z"
 },
 {
  "_exemplo": true,
  "nome_cliente": "SHOPEE (EXEMPLO)",
  "operacao": "SHOPEE - LINE HAUL",
  "codigo_sm": "9900011",
  "status_sm": "EM ANDAMENTO",
  "status_operacional": "Em Viagem Vazio",
  "data_cadastro_sm": "2026-10-28T03:00:00",
  "latitude": -22.7858,
  "longitude": -43.3117,
  "data_ultima_posicao": "2026-10-28T11:55:00",
  "velocidade": 45,
  "macro_vigente": "RETORNO VAZIO",
  "cidade_uf": "Duque de Caxias/RJ",
  "localizacao_atual": "CD Duque de Caxias",
  "rota": {
   "codigo": "R111",
   "descricao": "Cajamar/SP x CD Betim",
   "km_total": 557,
   "tempo_total": "5:30"
  },
  "origem": {
   "nome": "CD Cajamar",
   "eta_original": "2026-10-28T05:00:00",
   "eta_real": "2026-10-28T05:20:00",
   "entrada": "2026-10-28T04:00:00",
   "saida": "2026-10-28T05:00:00",
   "entrada_real": "2026-10-28T04:10:00",
   "saida_real": "2026-10-28T05:15:00"
  },
  "destino": {
   "nome": "CD Betim",
   "eta_original": "2026-10-28T15:47:00",
   "eta_real": null,
   "entrada": "2026-10-28T16:47:00",
   "saida": "2026-10-28T19:17:00",
   "entrada_real": null,
   "saida_real": null
  },
  "motoristas": [
   {
    "nome": "Motorista Exemplo 11",
    "cpf": "000.000.011-00",
    "vinculo": "AGREGADO"
   }
  ],
  "placas": [
   {
    "placa": "TSTE-011",
    "frota": null,
    "vinculo": "AGREGADO",
    "tipo": "CAVALO"
   },
   {
    "placa": "TSTC-011",
    "frota": null,
    "vinculo": "AGREGADO",
    "tipo": "CARRETA"
   }
  ],
  "paradas": [],
  "previsao_inicio": "2026-10-28T05:00:00",
  "previsao_fim": "2026-10-28T16:17:00",
  "inicio_real": "2026-10-28T05:15:00"
 },
 {
  "_exemplo": true,
  "nome_cliente": "SHOPEE (EXEMPLO)",
  "operacao": "SHOPEE - TRANSFERENCIA",
  "codigo_sm": "",
  "status_sm": null,
  "status_operacional": "Em Viagem Carregado",
  "data_cadastro_sm": null,
  "latitude": -22.8547,
  "longitude": -46.3178,
  "data_ultima_posicao": "28/10/2026 11:50",
  "velocidade": 58,
  "macro_vigente": "INICIO DE VIAGEM",
  "cidade_uf": "Extrema/MG",
  "localizacao_atual": "Rod. Fernão Dias km 946",
  "rota": null,
  "origem": null,
  "destino": null,
  "motoristas": [
   {
    "nome": "Motorista Exemplo 12",
    "cpf": "000.000.012-00",
    "vinculo": "FROTA"
   }
  ],
  "placas": [
   {
    "placa": "TSTE-012",
    "frota": "F112",
    "vinculo": "FROTA",
    "tipo": "CAVALO"
   },
   {
    "placa": "TSTC-012",
    "frota": null,
    "vinculo": "FROTA",
    "tipo": "CARRETA"
   }
  ],
  "paradas": [],
  "previsao_inicio": null,
  "previsao_fim": null,
  "inicio_real": null
 },
 {
  "_exemplo": true,
  "nome_cliente": "SHOPEE (EXEMPLO)",
  "operacao": "SHOPEE - LINE HAUL",
  "codigo_sm": "9900013",
  "status_sm": "EM ANDAMENTO",
  "status_operacional": "Carregando",
  "data_cadastro_sm": "2026-10-28T01:00:00-03:00",
  "latitude": -22.2266,
  "longitude": -45.9389,
  "data_ultima_posicao": "2026-10-28T11:58:00-03:00",
  "velocidade": 0,
  "macro_vigente": "INICIO CARREGAMENTO",
  "cidade_uf": "Pouso Alegre/MG",
  "localizacao_atual": "Rod. Fernão Dias km 860",
  "rota": {
   "codigo": "R113",
   "descricao": "Cajamar/SP x CD Campinas",
   "km_total": 631,
   "tempo_total": "7:30"
  },
  "origem": {
   "nome": "CD Cajamar",
   "eta_original": "2026-10-28T03:00:00-03:00",
   "eta_real": "2026-10-28T03:20:00-03:00",
   "entrada": "2026-10-28T02:00:00-03:00",
   "saida": "2026-10-28T03:00:00-03:00",
   "entrada_real": "2026-10-28T02:10:00-03:00",
   "saida_real": "2026-10-28T03:15:00-03:00"
  },
  "destino": {
   "nome": "CD Campinas",
   "eta_original": "2026-10-28T18:01:00-03:00",
   "eta_real": "2026-10-28T18:31:00-03:00",
   "entrada": "2026-10-28T19:01:00-03:00",
   "saida": "2026-10-28T21:31:00-03:00",
   "entrada_real": null,
   "saida_real": null
  },
  "motoristas": [
   {
    "nome": "Motorista Exemplo 13",
    "cpf": "000.000.013-00",
    "vinculo": "TERCEIRO"
   }
  ],
  "placas": [
   {
    "placa": "TSTE-013",
    "frota": null,
    "vinculo": "TERCEIRO",
    "tipo": "CAVALO"
   },
   {
    "placa": "TSTC-013",
    "frota": null,
    "vinculo": "TERCEIRO",
    "tipo": "CARRETA"
   }
  ],
  "paradas": [],
  "previsao_inicio": "2026-10-28T03:00:00-03:00",
  "previsao_fim": "2026-10-28T18:31:00-03:00",
  "inicio_real": "2026-10-28T03:15:00-03:00"
 },
 {
  "_exemplo": true,
  "nome_cliente": "SHOPEE (EXEMPLO)",
  "operacao": "SHOPEE - LINE HAUL",
  "codigo_sm": "9900014",
  "status_sm": "EM ANDAMENTO",
  "status_operacional": "Em Descarga",
  "data_cadastro_sm": "2026-10-28T03:00:00Z",
  "latitude": -19.9678,
  "longitude": -44.1983,
  "data_ultima_posicao": "2026-10-28T12:00:00Z",
  "velocidade": 0,
  "macro_vigente": "INICIO DESCARGA",
  "cidade_uf": "Betim/MG",
  "localizacao_atual": "CD Betim",
  "rota": {
   "codigo": "R114",
   "descricao": "Cajamar/SP x CD Barueri",
   "km_total": 668,
   "tempo_total": "8:30"
  },
  "origem": {
   "nome": "CD Cajamar",
   "eta_original": "2026-10-28T05:00:00Z",
   "eta_real": "2026-10-28T05:20:00Z",
   "entrada": "2026-10-28T04:00:00Z",
   "saida": "2026-10-28T05:00:00Z",
   "entrada_real": "2026-10-28T04:10:00Z",
   "saida_real": "2026-10-28T05:15:00Z"
  },
  "destino": {
   "nome": "CD Barueri",
   "eta_original": "2026-10-28T22:08:00Z",
   "eta_real": "2026-10-28T22:38:00Z",
   "entrada": "2026-10-28T23:08:00Z",
   "saida": "2026-10-29T01:38:00Z",
   "entrada_real": null,
   "saida_real": null
  },
  "motoristas": [
   {
    "nome": "Motorista Exemplo 14",
    "cpf": "000.000.014-00",
    "vinculo": "AGREGADO"
   }
  ],
  "placas": [
   {
    "placa": "TSTE-014",
    "frota": null,
    "vinculo": "AGREGADO",
    "tipo": "CAVALO"
   },
   {
    "placa": "TSTC-014",
    "frota": null,
    "vinculo": "AGREGADO",
    "tipo": "CARRETA"
   }
  ],
  "paradas": [],
  "previsao_inicio": "2026-10-28T05:00:00Z",
  "previsao_fim": "2026-10-28T22:38:00Z",
  "inicio_real": "2026-10-28T05:15:00Z"
 },
 {
  "_exemplo": true,
  "nome_cliente": "SHOPEE (EXEMPLO)",
  "operacao": "SHOPEE - LINE HAUL",
  "codigo_sm": "9900015",
  "status_sm": "PROGRAMADA",
  "status_operacional": "Sem Viagem",
  "data_cadastro_sm": "2026-10-27T23:00:00",
  "latitude": -19.932,
  "longitude": -44.0539,
  "data_ultima_posicao": "2026-10-28T11:48:00",
  "velocidade": 0,
  "macro_vigente": "PERNOITE",
  "cidade_uf": "Contagem/MG",
  "localizacao_atual": "Rod. Fernão Dias km 492",
  "rota": {
   "codigo": "R115",
   "descricao": "Cajamar/SP x CD Duque de Caxias",
   "km_total": 705,
   "tempo_total": "9:30"
  },
  "origem": {
   "nome": "CD Cajamar",
   "eta_original": "2026-10-28T01:00:00",
   "eta_real": "2026-10-28T01:20:00",
   "entrada": "2026-10-28T00:00:00",
   "saida": "2026-10-28T01:00:00",
   "entrada_real": "2026-10-28T00:10:00",
   "saida_real": "2026-10-28T01:15:00"
  },
  "destino": {
   "nome": "CD Duque de Caxias",
   "eta_original": "2026-10-28T20:15:00",
   "eta_real": "2026-10-28T20:45:00",
   "entrada": "2026-10-28T21:15:00",
   "saida": "2026-10-28T23:45:00",
   "entrada_real": null,
   "saida_real": null
  },
  "motoristas": [
   {
    "nome": "Motorista Exemplo 15",
    "cpf": "000.000.015-00",
    "vinculo": "FROTA"
   }
  ],
  "placas": [
   {
    "placa": "TSTE-015",
    "frota": "F115",
    "vinculo": "FROTA",
    "tipo": "CAVALO"
   }
  ],
  "paradas": [
   {
    "nome": "Posto de apoio",
    "sequencia": 1,
    "eta_original": "2026-10-28T03:00:00",
    "eta_real": "2026-10-28T03:10:00",
    "entrada": null,
    "saida": null,
    "entrada_real": "2026-10-28T03:05:00",
    "saida_real": "2026-10-28T03:40:00"
   },
   {
    "nome": "CD Duque de Caxias",
    "sequencia": 2,
    "eta_original": "2026-10-28T20:15:00",
    "eta_real": "2026-10-28T20:45:00",
    "entrada": null,
    "saida": null,
    "entrada_real": null,
    "saida_real": null
   }
  ],
  "previsao_inicio": "2026-10-28T01:00:00",
  "previsao_fim": "2026-10-28T20:45:00",
  "inicio_real": "2026-10-28T01:15:00"
 },
 {
  "_exemplo": true,
  "nome_cliente": "SHOPEE (EXEMPLO)",
  "operacao": "SHOPEE - TRANSFERENCIA",
  "codigo_sm": "-",
  "status_sm": null,
  "status_operacional": "Em Viagem Carregado",
  "data_cadastro_sm": null,
  "latitude": -24.4979,
  "longitude": -47.8449,
  "data_ultima_posicao": "28/10/2026 11:56",
  "velocidade": 64,
  "macro_vigente": "INICIO DE VIAGEM",
  "cidade_uf": "Registro/SP",
  "localizacao_atual": "Rod. Régis Bittencourt km 445",
  "rota": null,
  "origem": null,
  "destino": null,
  "motoristas": [
   {
    "nome": "Motorista Exemplo 16",
    "cpf": "000.000.016-00",
    "vinculo": "TERCEIRO"
   }
  ],
  "placas": [
   {
    "placa": "TSTE-016",
    "frota": null,
    "vinculo": "TERCEIRO",
    "tipo": "CAVALO"
   },
   {
    "placa": "TSTC-016",
    "frota": null,
    "vinculo": "FROTA",
    "tipo": "CARRETA"
   }
  ],
  "paradas": [],
  "previsao_inicio": null,
  "previsao_fim": null,
  "inicio_real": null
 },
 {
  "_exemplo": true,
  "nome_cliente": "SHOPEE (EXEMPLO)",
  "operacao": "SHOPEE - LINE HAUL",
  "codigo_sm": "9900017",
  "status_sm": "EM ANDAMENTO",
  "status_operacional": "Em Viagem Vazio",
  "data_cadastro_sm": "2026-10-27T21:00:00-03:00",
  "latitude": -25.4284,
  "longitude": -49.2733,
  "data_ultima_posicao": "2026-10-28T11:51:00-03:00",
  "velocidade": 77,
  "macro_vigente": "RETORNO VAZIO",
  "cidade_uf": "Curitiba/PR",
  "localizacao_atual": "CD Curitiba",
  "rota": {
   "codigo": "R117",
   "descricao": "Cajamar/SP x CD Curitiba",
   "km_total": 779,
   "tempo_total": "11:30"
  },
  "origem": {
   "nome": "CD Cajamar",
   "eta_original": "2026-10-27T23:00:00-03:00",
   "eta_real": "2026-10-27T23:20:00-03:00",
   "entrada": "2026-10-27T22:00:00-03:00",
   "saida": "2026-10-27T23:00:00-03:00",
   "entrada_real": "2026-10-27T22:10:00-03:00",
   "saida_real": "2026-10-27T23:15:00-03:00"
  },
  "destino": {
   "nome": "CD Curitiba",
   "eta_original": "2026-10-28T22:29:00-03:00",
   "eta_real": "2026-10-28T22:59:00-03:00",
   "entrada": "2026-10-28T23:29:00-03:00",
   "saida": "2026-10-29T01:59:00-03:00",
   "entrada_real": null,
   "saida_real": null
  },
  "motoristas": [
   {
    "nome": "Motorista Exemplo 17",
    "cpf": "000.000.017-00",
    "vinculo": "AGREGADO"
   }
  ],
  "placas": [
   {
    "placa": "TSTE-017",
    "frota": null,
    "vinculo": "AGREGADO",
    "tipo": "CAVALO"
   },
   {
    "placa": "TSTC-017",
    "frota": null,
    "vinculo": "AGREGADO",
    "tipo": "CARRETA"
   }
  ],
  "paradas": [],
  "previsao_inicio": "2026-10-27T23:00:00-03:00",
  "previsao_fim": "2026-10-28T22:59:00-03:00",
  "inicio_real": "2026-10-27T23:15:00-03:00"
 },
 {
  "_exemplo": true,
  "nome_cliente": "SHOPEE (EXEMPLO)",
  "operacao": "SHOPEE - LINE HAUL",
  "codigo_sm": "9900018",
  "status_sm": "EM ANDAMENTO",
  "status_operacional": "Em Viagem Carregado",
  "data_cadastro_sm": "2026-10-27T23:00:00Z",
  "latitude": -25.5302,
  "longitude": -49.2061,
  "data_ultima_posicao": "2026-10-28T14:46:00Z",
  "velocidade": 44,
  "macro_vigente": "INICIO DE VIAGEM",
  "cidade_uf": "São José dos Pinhais/PR",
  "localizacao_atual": "BR-376 km 630",
  "rota": {
   "codigo": "R118",
   "descricao": "Cajamar/SP x CD Campinas",
   "km_total": 816,
   "tempo_total": "3:30"
  },
  "origem": {
   "nome": "CD Cajamar",
   "eta_original": "2026-10-28T01:00:00Z",
   "eta_real": "2026-10-28T01:20:00Z",
   "entrada": "2026-10-28T00:00:00Z",
   "saida": "2026-10-28T01:00:00Z",
   "entrada_real": "2026-10-28T00:10:00Z",
   "saida_real": "2026-10-28T01:15:00Z"
  },
  "destino": {
   "nome": "CD Campinas",
   "eta_original": "2026-10-28T16:36:00Z",
   "eta_real": "2026-10-28T17:06:00Z",
   "entrada": "2026-10-28T17:36:00Z",
   "saida": "2026-10-28T20:06:00Z",
   "entrada_real": null,
   "saida_real": null
  },
  "motoristas": [
   {
    "nome": "Motorista Exemplo 18",
    "cpf": "000.000.018-00",
    "vinculo": "FROTA"
   }
  ],
  "placas": [
   {
    "placa": "TSTE-018",
    "frota": "F118",
    "vinculo": "FROTA",
    "tipo": "CAVALO"
   },
   {
    "placa": "TSTC-018",
    "frota": null,
    "vinculo": "FROTA",
    "tipo": "CARRETA"
   }
  ],
  "paradas": [
   {
    "nome": "Posto de apoio",
    "sequencia": 1,
    "eta_original": "2026-10-28T03:00:00Z",
    "eta_real": "2026-10-28T03:10:00Z",
    "entrada": null,
    "saida": null,
    "entrada_real": "2026-10-28T03:05:00Z",
    "saida_real": "2026-10-28T03:40:00Z"
   },
   {
    "nome": "CD Campinas",
    "sequencia": 2,
    "eta_original": "2026-10-28T16:36:00Z",
    "eta_real": "2026-10-28T17:06:00Z",
    "entrada": null,
    "saida": null,
    "entrada_real": null,
    "saida_real": null
   }
  ],
  "previsao_inicio": "2026-10-28T01:00:00Z",
  "previsao_fim": "2026-10-28T17:06:00Z",
  "inicio_real": "2026-10-28T01:15:00Z"
 },
 {
  "_exemplo": true,
  "nome_cliente": "SHOPEE (EXEMPLO)",
  "operacao": "SHOPEE - LINE HAUL",
  "codigo_sm": "9900019",
  "status_sm": "EM ANDAMENTO",
  "status_operacional": "Carregando",
  "data_cadastro_sm": "2026-10-27T19:00:00",
  "latitude": -23.5015,
  "longitude": -47.4526,
  "data_ultima_posicao": "2026-10-28T11:54:00",
  "velocidade": 0,
  "macro_vigente": "INICIO CARREGAMENTO",
  "cidade_uf": "Sorocaba/SP",
  "localizacao_atual": "Rod. Castelo Branco km 90",
  "rota": {
   "codigo": "R119",
   "descricao": "Cajamar/SP x CD Barueri",
   "km_total": 853,
   "tempo_total": "4:30"
  },
  "origem": {
   "nome": "CD Cajamar",
   "eta_original": "2026-10-27T21:00:00",
   "eta_real": "2026-10-27T21:20:00",
   "entrada": "2026-10-27T20:00:00",
   "saida": "2026-10-27T21:00:00",
   "entrada_real": "2026-10-27T20:10:00",
   "saida_real": "2026-10-27T21:15:00"
  },
  "destino": {
   "nome": "CD Barueri",
   "eta_original": "2026-10-28T14:43:00",
   "eta_real": "2026-10-28T15:13:00",
   "entrada": "2026-10-28T15:43:00",
   "saida": "2026-10-28T18:13:00",
   "entrada_real": null,
   "saida_real": null
  },
  "motoristas": [
   {
    "nome": "Motorista Exemplo 19",
    "cpf": "000.000.019-00",
    "vinculo": "TERCEIRO"
   }
  ],
  "placas": [
   {
    "placa": "TSTE-019",
    "frota": null,
    "vinculo": "TERCEIRO",
    "tipo": "CAVALO"
   },
   {
    "placa": "TSTC-019",
    "frota": null,
    "vinculo": "TERCEIRO",
    "tipo": "CARRETA"
   }
  ],
  "paradas": [],
  "previsao_inicio": "2026-10-27T21:00:00",
  "previsao_fim": "2026-10-28T15:13:00",
  "inicio_real": "2026-10-27T21:15:00"
 },
 {
  "_exemplo": true,
  "nome_cliente": "SHOPEE (EXEMPLO)",
  "operacao": "SHOPEE - TRANSFERENCIA",
  "codigo_sm": null,
  "status_sm": null,
  "status_operacional": "Em Descarga",
  "data_cadastro_sm": null,
  "latitude": -21.1704,
  "longitude": -47.8103,
  "data_ultima_posicao": "28/10/2026 11:49",
  "velocidade": 0,
  "macro_vigente": "INICIO DESCARGA",
  "cidade_uf": "Ribeirão Preto/SP",
  "localizacao_atual": "Rod. Anhanguera km 310",
  "rota": null,
  "origem": null,
  "destino": null,
  "motoristas": [
   {
    "nome": "Motorista Exemplo 20",
    "cpf": "000.000.020-00",
    "vinculo": "AGREGADO"
   }
  ],
  "placas": [
   {
    "placa": "TSTE-020",
    "frota": null,
    "vinculo": "AGREGADO",
    "tipo": "CAVALO"
   }
  ],
  "paradas": [],
  "previsao_inicio": null,
  "previsao_fim": null,
  "inicio_real": null
 },
 {
  "_exemplo": true,
  "nome_cliente": "SHOPEE (EXEMPLO)",
  "operacao": "SHOPEE - LINE HAUL",
  "codigo_sm": "9900021",
  "status_sm": "PROGRAMADA",
  "status_operacional": "Sem Viagem",
  "data_cadastro_sm": "2026-10-28T03:00:00-03:00",
  "latitude": -23.5057,
  "longitude": -46.879,
  "data_ultima_posicao": "2026-10-26T12:00:00-03:00",
  "velocidade": 0,
  "macro_vigente": "PERNOITE",
  "cidade_uf": "Barueri/SP",
  "localizacao_atual": "CD Barueri",
  "rota": {
   "codigo": "R121",
   "descricao": "Cajamar/SP x CD Betim",
   "km_total": 927,
   "tempo_total": "6:30"
  },
  "origem": {
   "nome": "CD Cajamar",
   "eta_original": "2026-10-28T05:00:00-03:00",
   "eta_real": "2026-10-28T05:20:00-03:00",
   "entrada": "2026-10-28T04:00:00-03:00",
   "saida": "2026-10-28T05:00:00-03:00",
   "entrada_real": "2026-10-28T04:10:00-03:00",
   "saida_real": "2026-10-28T05:15:00-03:00"
  },
  "destino": {
   "nome": "CD Betim",
   "eta_original": "2026-10-28T16:57:00-03:00",
   "eta_real": "2026-10-28T17:27:00-03:00",
   "entrada": "2026-10-28T17:57:00-03:00",
   "saida": "2026-10-28T20:27:00-03:00",
   "entrada_real": null,
   "saida_real": null
  },
  "motoristas": [
   {
    "nome": "Motorista Exemplo 21",
    "cpf": "000.000.021-00",
    "vinculo": "FROTA"
   }
  ],
  "placas": [
   {
    "placa": "TSTE-021",
    "frota": "F121",
    "vinculo": "FROTA",
    "tipo": "CAVALO"
   },
   {
    "placa": "TSTC-021",
    "frota": null,
    "vinculo": "FROTA",
    "tipo": "CARRETA"
   }
  ],
  "paradas": [
   {
    "nome": "Posto de apoio",
    "sequencia": 1,
    "eta_original": "2026-10-28T07:00:00-03:00",
    "eta_real": "2026-10-28T07:10:00-03:00",
    "entrada": null,
    "saida": null,
    "entrada_real": "2026-10-28T07:05:00-03:00",
    "saida_real": "2026-10-28T07:40:00-03:00"
   },
   {
    "nome": "CD Betim",
    "sequencia": 2,
    "eta_original": "2026-10-28T16:57:00-03:00",
    "eta_real": "2026-10-28T17:27:00-03:00",
    "entrada": null,
    "saida": null,
    "entrada_real": null,
    "saida_real": null
   }
  ],
  "previsao_inicio": "2026-10-28T05:00:00-03:00",
  "previsao_fim": "2026-10-28T17:27:00-03:00",
  "inicio_real": "2026-10-28T05:15:00-03:00"
 },
 {
  "_exemplo": true,
  "nome_cliente": "SHOPEE (EXEMPLO)",
  "operacao": "SHOPEE - LINE HAUL",
  "codigo_sm": "9900022",
  "status_sm": "EM ANDAMENTO",
  "status_operacional": "Em Viagem Carregado",
  "data_cadastro_sm": "2026-10-28T05:00:00Z",
  "latitude": -23.153,
  "longitude": -47.0577,
  "data_ultima_posicao": "2026-10-28T14:52:00Z",
  "velocidade": 50,
  "macro_vigente": "INICIO DE VIAGEM",
  "cidade_uf": "Itupeva/SP",
  "localizacao_atual": "CD Itupeva",
  "rota": {
   "codigo": "R122",
   "descricao": "Cajamar/SP x CD Curitiba",
   "km_total": 964,
   "tempo_total": "7:30"
  },
  "origem": {
   "nome": "CD Cajamar",
   "eta_original": "2026-10-28T07:00:00Z",
   "eta_real": "2026-10-28T07:20:00Z",
   "entrada": "2026-10-28T06:00:00Z",
   "saida": "2026-10-28T07:00:00Z",
   "entrada_real": "2026-10-28T06:10:00Z",
   "saida_real": "2026-10-28T07:15:00Z"
  },
  "destino": {
   "nome": "CD Curitiba",
   "eta_original": "2026-10-28T21:04:00Z",
   "eta_real": "2026-10-28T21:34:00Z",
   "entrada": "2026-10-28T22:04:00Z",
   "saida": "2026-10-29T00:34:00Z",
   "entrada_real": null,
   "saida_real": null
  },
  "motoristas": [
   {
    "nome": "Motorista Exemplo 22",
    "cpf": "000.000.022-00",
    "vinculo": "TERCEIRO"
   }
  ],
  "placas": [
   {
    "placa": "TSTE-022",
    "frota": null,
    "vinculo": "TERCEIRO",
    "tipo": "CAVALO"
   },
   {
    "placa": "TSTC-022",
    "frota": null,
    "vinculo": "TERCEIRO",
    "tipo": "CARRETA"
   }
  ],
  "paradas": [],
  "previsao_inicio": "2026-10-28T07:00:00Z",
  "previsao_fim": "2026-10-28T21:34:00Z",
  "inicio_real": "2026-10-28T07:15:00Z"
 },
 {
  "_exemplo": true,
  "nome_cliente": "SHOPEE (EXEMPLO)",
  "operacao": "SHOPEE - LINE HAUL",
  "codigo_sm": "9900023",
  "status_sm": "EM ANDAMENTO",
  "status_operacional": "Em Viagem Vazio",
  "data_cadastro_sm": "2026-10-28T01:00:00",
  "latitude": -18.9186,
  "longitude": -48.2772,
  "data_ultima_posicao": "2026-10-28T11:47:00",
  "velocidade": 63,
  "macro_vigente": "RETORNO VAZIO",
  "cidade_uf": "Uberlândia/MG",
  "localizacao_atual": "BR-050 km 70",
  "rota": {
   "codigo": "R123",
   "descricao": "Cajamar/SP x CD Campinas",
   "km_total": 1001,
   "tempo_total": "8:30"
  },
  "origem": {
   "nome": "CD Cajamar",
   "eta_original": "2026-10-28T03:00:00",
   "eta_real": "2026-10-28T03:20:00",
   "entrada": "2026-10-28T02:00:00",
   "saida": "2026-10-28T03:00:00",
   "entrada_real": "2026-10-28T02:10:00",
   "saida_real": "2026-10-28T03:15:00"
  },
  "destino": {
   "nome": "CD Campinas",
   "eta_original": "2026-10-28T19:11:00",
   "eta_real": null,
   "entrada": "2026-10-28T20:11:00",
   "saida": "2026-10-28T22:41:00",
   "entrada_real": null,
   "saida_real": null
  },
  "motoristas": [
   {
    "nome": "Motorista Exemplo 23",
    "cpf": "000.000.023-00",
    "vinculo": "AGREGADO"
   }
  ],
  "placas": [
   {
    "placa": "TSTE-023",
    "frota": null,
    "vinculo": "AGREGADO",
    "tipo": "CAVALO"
   },
   {
    "placa": "TSTC-023",
    "frota": null,
    "vinculo": "AGREGADO",
    "tipo": "CARRETA"
   }
  ],
  "paradas": [],
  "previsao_inicio": "2026-10-28T03:00:00",
  "previsao_fim": "2026-10-28T19:41:00",
  "inicio_real": "2026-10-28T03:15:00"
 },
 {
  "_exemplo": true,
  "nome_cliente": "SHOPEE (EXEMPLO)",
  "operacao": "SHOPEE - TRANSFERENCIA",
  "codigo_sm": "9900024",
  "status_sm": "EM ANDAMENTO",
  "status_operacional": "Em Viagem Carregado",
  "data_cadastro_sm": "28/10/2026 00:00",
  "latitude": -21.7642,
  "longitude": -43.3496,
  "data_ultima_posicao": "28/10/2026 11:55",
  "velocidade": 76,
  "macro_vigente": "INICIO DE VIAGEM",
  "cidade_uf": "Juiz de Fora/MG",
  "localizacao_atual": "BR-040 km 770",
  "rota": {
   "codigo": "R124",
   "descricao": "Cajamar/SP x CD Barueri",
   "km_total": 1038,
   "tempo_total": "9:30"
  },
  "origem": {
   "nome": "CD Cajamar",
   "eta_original": "28/10/2026 02:00",
   "eta_real": "28/10/2026 02:20",
   "entrada": "28/10/2026 01:00",
   "saida": "28/10/2026 02:00",
   "entrada_real": "28/10/2026 01:10",
   "saida_real": "28/10/2026 02:15"
  },
  "destino": {
   "nome": "CD Barueri",
   "eta_original": "28/10/2026 20:18",
   "eta_real": "28/10/2026 20:48",
   "entrada": "28/10/2026 21:18",
   "saida": "28/10/2026 23:48",
   "entrada_real": null,
   "saida_real": null
  },
  "motoristas": [
   {
    "nome": "Motorista Exemplo 24",
    "cpf": "000.000.024-00",
    "vinculo": "FROTA"
   }
  ],
  "placas": [
   {
    "placa": "TSTE-024",
    "frota": "F124",
    "vinculo": "FROTA",
    "tipo": "CAVALO"
   },
   {
    "placa": "TSTC-024",
    "frota": null,
    "vinculo": "FROTA",
    "tipo": "CARRETA"
   }
  ],
  "paradas": [
   {
    "nome": "Posto de apoio",
    "sequencia": 1,
    "eta_original": "28/10/2026 04:00",
    "eta_real": "28/10/2026 04:10",
    "entrada": null,
    "saida": null,
    "entrada_real": "28/10/2026 04:05",
    "saida_real": "28/10/2026 04:40"
   },
   {
    "nome": "CD Barueri",
    "sequencia": 2,
    "eta_original": "28/10/2026 20:18",
    "eta_real": "28/10/2026 20:48",
    "entrada": null,
    "saida": null,
    "entrada_real": null,
    "saida_real": null
   }
  ],
  "previsao_inicio": "28/10/2026 02:00",
  "previsao_fim": "28/10/2026 20:48",
  "inicio_real": "28/10/2026 02:15"
 },
 {
  "_exemplo": true,
  "nome_cliente": "SHOPEE (EXEMPLO)",
  "operacao": "SHOPEE - LINE HAUL",
  "codigo_sm": "9900025",
  "status_sm": "EM ANDAMENTO",
  "status_operacional": "Carregando",
  "data_cadastro_sm": "2026-10-27T23:00:00-03:00",
  "latitude": -23.9608,
  "longitude": -46.3336,
  "data_ultima_posicao": "2026-10-28T11:50:00-03:00",
  "velocidade": 0,
  "macro_vigente": "INICIO CARREGAMENTO",
  "cidade_uf": "Santos/SP",
  "localizacao_atual": "Porto de Santos",
  "rota": {
   "codigo": "R125",
   "descricao": "Cajamar/SP x CD Duque de Caxias",
   "km_total": 1075,
   "tempo_total": "10:30"
  },
  "origem": {
   "nome": "CD Cajamar",
   "eta_original": "2026-10-28T01:00:00-03:00",
   "eta_real": "2026-10-28T01:20:00-03:00",
   "entrada": "2026-10-28T00:00:00-03:00",
   "saida": "2026-10-28T01:00:00-03:00",
   "entrada_real": "2026-10-28T00:10:00-03:00",
   "saida_real": "2026-10-28T01:15:00-03:00"
  },
  "destino": {
   "nome": "CD Duque de Caxias",
   "eta_original": "2026-10-28T21:25:00-03:00",
   "eta_real": "2026-10-28T21:55:00-03:00",
   "entrada": "2026-10-28T22:25:00-03:00",
   "saida": "2026-10-29T00:55:00-03:00",
   "entrada_real": null,
   "saida_real": null
  },
  "motoristas": [
   {
    "nome": "Motorista Exemplo 25",
    "cpf": "000.000.025-00",
    "vinculo": "TERCEIRO"
   }
  ],
  "placas": [
   {
    "placa": "TSTE-025",
    "frota": null,
    "vinculo": "TERCEIRO",
    "tipo": "CAVALO"
   }
  ],
  "paradas": [],
  "previsao_inicio": "2026-10-28T01:00:00-03:00",
  "previsao_fim": "2026-10-28T21:55:00-03:00",
  "inicio_real": "2026-10-28T01:15:00-03:00"
 },
 {
  "_exemplo": true,
  "nome_cliente": "SHOPEE (EXEMPLO)",
  "operacao": "SHOPEE - LINE HAUL",
  "codigo_sm": "9900026",
  "status_sm": "EM ANDAMENTO",
  "status_operacional": "Em Descarga",
  "data_cadastro_sm": "2026-10-28T01:00:00Z",
  "latitude": -23.0264,
  "longitude": -45.5553,
  "data_ultima_posicao": "2026-10-28T14:58:00Z",
  "velocidade": 0,
  "macro_vigente": "INICIO DESCARGA",
  "cidade_uf": "Taubaté/SP",
  "localizacao_atual": "Rod. Presidente Dutra km 105",
  "rota": {
   "codigo": "R126",
   "descricao": "Cajamar/SP x CD Betim",
   "km_total": 1112,
   "tempo_total": "11:30"
  },
  "origem": {
   "nome": "CD Cajamar",
   "eta_original": "2026-10-28T03:00:00Z",
   "eta_real": "2026-10-28T03:20:00Z",
   "entrada": "2026-10-28T02:00:00Z",
   "saida": "2026-10-28T03:00:00Z",
   "entrada_real": "2026-10-28T02:10:00Z",
   "saida_real": "2026-10-28T03:15:00Z"
  },
  "destino": {
   "nome": "CD Betim",
   "eta_original": "2026-10-29T00:32:00Z",
   "eta_real": "2026-10-29T01:02:00Z",
   "entrada": "2026-10-29T01:32:00Z",
   "saida": "2026-10-29T04:02:00Z",
   "entrada_real": null,
   "saida_real": null
  },
  "motoristas": [
   {
    "nome": "Motorista Exemplo 26",
    "cpf": "000.000.026-00",
    "vinculo": "AGREGADO"
   }
  ],
  "placas": [
   {
    "placa": "TSTE-026",
    "frota": null,
    "vinculo": "AGREGADO",
    "tipo": "CAVALO"
   },
   {
    "placa": "TSTC-026",
    "frota": null,
    "vinculo": "AGREGADO",
    "tipo": "CARRETA"
   }
  ],
  "paradas": [],
  "previsao_inicio": "2026-10-28T03:00:00Z",
  "previsao_fim": "2026-10-29T01:02:00Z",
  "inicio_real": "2026-10-28T03:15:00Z"
 },
 {
  "_exemplo": true,
  "nome_cliente": "SHOPEE (EXEMPLO)",
  "operacao": "SHOPEE - LINE HAUL",
  "codigo_sm": "9900027",
  "status_sm": "PROGRAMADA",
  "status_operacional": "Sem Viagem",
  "data_cadastro_sm": "2026-10-27T21:00:00",
  "latitude": -22.91,
  "longitude": -47.065,
  "data_ultima_posicao": "2026-10-28T11:53:00",
  "velocidade": 0,
  "macro_vigente": "PERNOITE",
  "cidade_uf": "Campinas/SP",
  "localizacao_atual": "CD Campinas",
  "rota": {
   "codigo": "R127",
   "descricao": "Cajamar/SP x CD Curitiba",
   "km_total": 1149,
   "tempo_total": "3:30"
  },
  "origem": {
   "nome": "CD Cajamar",
   "eta_original": "2026-10-27T23:00:00",
   "eta_real": "2026-10-27T23:20:00",
   "entrada": "2026-10-27T22:00:00",
   "saida": "2026-10-27T23:00:00",
   "entrada_real": "2026-10-27T22:10:00",
   "saida_real": "2026-10-27T23:15:00"
  },
  "destino": {
   "nome": "CD Curitiba",
   "eta_original": "2026-10-28T13:39:00",
   "eta_real": "2026-10-28T14:09:00",
   "entrada": "2026-10-28T14:39:00",
   "saida": "2026-10-28T17:09:00",
   "entrada_real": null,
   "saida_real": null
  },
  "motoristas": [
   {
    "nome": "Motorista Exemplo 27",
    "cpf": "000.000.027-00",
    "vinculo": "FROTA"
   }
  ],
  "placas": [
   {
    "placa": "TSTE-027",
    "frota": "F127",
    "vinculo": "FROTA",
    "tipo": "CAVALO"
   },
   {
    "placa": "TSTC-027",
    "frota": null,
    "vinculo": "FROTA",
    "tipo": "CARRETA"
   }
  ],
  "paradas": [
   {
    "nome": "Posto de apoio",
    "sequencia": 1,
    "eta_original": "2026-10-28T01:00:00",
    "eta_real": "2026-10-28T01:10:00",
    "entrada": null,
    "saida": null,
    "entrada_real": "2026-10-28T01:05:00",
    "saida_real": "2026-10-28T01:40:00"
   },
   {
    "nome": "CD Curitiba",
    "sequencia": 2,
    "eta_original": "2026-10-28T13:39:00",
    "eta_real": "2026-10-28T14:09:00",
    "entrada": null,
    "saida": null,
    "entrada_real": null,
    "saida_real": null
   }
  ],
  "previsao_inicio": "2026-10-27T23:00:00",
  "previsao_fim": "2026-10-28T14:09:00",
  "inicio_real": "2026-10-27T23:15:00"
 },
 {
  "_exemplo": true,
  "nome_cliente": "SHOPEE (EXEMPLO)",
  "operacao": "SHOPEE - TRANSFERENCIA",
  "codigo_sm": "9900028",
  "status_sm": "EM ANDAMENTO",
  "status_operacional": "Em Viagem Carregado",
  "data_cadastro_sm": "27/10/2026 20:00",
  "latitude": -23.1171,
  "longitude": -46.5563,
  "data_ultima_posicao": "28/10/2026 11:48",
  "velocidade": 82,
  "macro_vigente": "INICIO DE VIAGEM",
  "cidade_uf": "Atibaia/SP",
  "localizacao_atual": "Rod. Fernão Dias km 37",
  "rota": {
   "codigo": "R128",
   "descricao": "Cajamar/SP x CD Campinas",
   "km_total": 1186,
   "tempo_total": "4:30"
  },
  "origem": {
   "nome": "CD Cajamar",
   "eta_original": "27/10/2026 22:00",
   "eta_real": "27/10/2026 22:20",
   "entrada": "27/10/2026 21:00",
   "saida": "27/10/2026 22:00",
   "entrada_real": "27/10/2026 21:10",
   "saida_real": "27/10/2026 22:15"
  },
  "destino": {
   "nome": "CD Campinas",
   "eta_original": "28/10/2026 14:46",
   "eta_real": "28/10/2026 15:16",
   "entrada": "28/10/2026 15:46",
   "saida": "28/10/2026 18:16",
   "entrada_real": null,
   "saida_real": null
  },
  "motoristas": [
   {
    "nome": "Motorista Exemplo 28",
    "cpf": "000.000.028-00",
    "vinculo": "TERCEIRO"
   }
  ],
  "placas": [
   {
    "placa": "TSTE-028",
    "frota": null,
    "vinculo": "TERCEIRO",
    "tipo": "CAVALO"
   },
   {
    "placa": "TSTC-028",
    "frota": null,
    "vinculo": "FROTA",
    "tipo": "CARRETA"
   }
  ],
  "paradas": [],
  "previsao_inicio": "27/10/2026 22:00",
  "previsao_fim": "28/10/2026 15:16",
  "inicio_real": "27/10/2026 22:15"
 },
 {
  "_exemplo": true,
  "nome_cliente": "SHOPEE (EXEMPLO)",
  "operacao": "SHOPEE - LINE HAUL",
  "codigo_sm": "9900029",
  "status_sm": "PROGRAMADA",
  "status_operacional": "Sem Viagem",
  "data_cadastro_sm": "28/10/2026 07:00",
  "latitude": null,
  "longitude": null,
  "data_ultima_posicao": null,
  "velocidade": null,
  "macro_vigente": null,
  "cidade_uf": null,
  "localizacao_atual": null,
  "rota": null,
  "origem": {
   "nome": "CD Cajamar"
  },
  "destino": {
   "nome": "CD Betim",
   "eta_real": null
  },
  "motoristas": [],
  "placas": [],
  "paradas": [],
  "previsao_inicio": "28/10/2026 16:00",
  "previsao_fim": null,
  "inicio_real": null
 },
 {
  "_exemplo": true,
  "nome_cliente": "SHOPEE (EXEMPLO)",
  "codigo_sm": 0,
  "status_operacional": "Sem Viagem",
  "latitude": -23.5,
  "longitude": -46.6,
  "data_ultima_posicao": "2026-10-28T14:57:00Z",
  "velocidade": 0,
  "motoristas": [
   {
    "nome": "Motorista Exemplo 30",
    "cpf": "000.000.030-00",
    "vinculo": "TERCEIRO"
   }
  ],
  "placas": null,
  "paradas": null
 }
]
$amostra$::jsonb);

-- Desloca as datas para o "agora" real.
update torre.veiculos_atual
   set data_cadastro_sm     = data_cadastro_sm     + (now() - '2026-10-28 12:00:00-03'::timestamptz),
       data_ultima_posicao  = data_ultima_posicao  + (now() - '2026-10-28 12:00:00-03'::timestamptz),
       origem_eta_original  = origem_eta_original  + (now() - '2026-10-28 12:00:00-03'::timestamptz),
       origem_eta_real      = origem_eta_real      + (now() - '2026-10-28 12:00:00-03'::timestamptz),
       origem_entrada       = origem_entrada       + (now() - '2026-10-28 12:00:00-03'::timestamptz),
       origem_saida         = origem_saida         + (now() - '2026-10-28 12:00:00-03'::timestamptz),
       origem_entrada_real  = origem_entrada_real  + (now() - '2026-10-28 12:00:00-03'::timestamptz),
       origem_saida_real    = origem_saida_real    + (now() - '2026-10-28 12:00:00-03'::timestamptz),
       destino_eta_original = destino_eta_original + (now() - '2026-10-28 12:00:00-03'::timestamptz),
       destino_eta_real     = destino_eta_real     + (now() - '2026-10-28 12:00:00-03'::timestamptz),
       destino_entrada      = destino_entrada      + (now() - '2026-10-28 12:00:00-03'::timestamptz),
       destino_saida        = destino_saida        + (now() - '2026-10-28 12:00:00-03'::timestamptz),
       destino_entrada_real = destino_entrada_real + (now() - '2026-10-28 12:00:00-03'::timestamptz),
       destino_saida_real   = destino_saida_real   + (now() - '2026-10-28 12:00:00-03'::timestamptz),
       previsao_inicio      = previsao_inicio      + (now() - '2026-10-28 12:00:00-03'::timestamptz),
       previsao_fim         = previsao_fim         + (now() - '2026-10-28 12:00:00-03'::timestamptz),
       inicio_real          = inicio_real          + (now() - '2026-10-28 12:00:00-03'::timestamptz)
 where bruto ? '_exemplo';

update torre.paradas_atual
   set eta_original = eta_original + (now() - '2026-10-28 12:00:00-03'::timestamptz),
       eta_real     = eta_real     + (now() - '2026-10-28 12:00:00-03'::timestamptz),
       entrada      = entrada      + (now() - '2026-10-28 12:00:00-03'::timestamptz),
       saida        = saida        + (now() - '2026-10-28 12:00:00-03'::timestamptz),
       entrada_real = entrada_real + (now() - '2026-10-28 12:00:00-03'::timestamptz),
       saida_real   = saida_real   + (now() - '2026-10-28 12:00:00-03'::timestamptz)
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
