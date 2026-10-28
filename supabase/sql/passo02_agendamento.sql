-- =============================================================================
-- Torre de Controle Shopee - Passo 02: agendamento (pg_cron + pg_net + Vault)
-- =============================================================================
-- Rodar no SQL Editor DEPOIS do passo 01, de publicar a função sincronizar-atlas
-- e de cadastrar os 2 segredos no Vault (seção 0 abaixo).
--
-- A URL da função e o CRON_SECRET NÃO ficam escritos aqui: são lidos do Vault
-- na hora de cada chamada. Trocar de projeto/conta = só recadastrar o Vault.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 0. Cadastrar os segredos no Vault (UMA vez; NÃO salve este trecho com valores)
-- -----------------------------------------------------------------------------
-- Rode no SQL Editor trocando os textos entre <...>, e apague a consulta do
-- histórico do SQL Editor depois. Nunca commite os valores.
--
--   select vault.create_secret('<URL da função, ex.: https://<ref>.supabase.co/functions/v1/sincronizar-atlas>',
--                              'torre_url_sincronizar_atlas', 'URL da função sincronizar-atlas');
--   select vault.create_secret('<o mesmo valor do secret CRON_SECRET da função>',
--                              'torre_cron_secret', 'Cabeçalho x-cron-secret da função sincronizar-atlas');
--
-- Para trocar um valor depois:
--   select vault.update_secret((select id from vault.secrets where name = 'torre_cron_secret'), '<novo valor>');
--
-- Para conferir que existem (sem mostrar o valor):
--   select name, created_at, updated_at from vault.secrets where name like 'torre_%';


-- -----------------------------------------------------------------------------
-- 1. Extensões
-- -----------------------------------------------------------------------------
create extension if not exists pg_cron with schema pg_catalog;
create extension if not exists pg_net with schema extensions;


-- -----------------------------------------------------------------------------
-- 2. Função que dispara a sincronização (lê URL e segredo do Vault)
-- -----------------------------------------------------------------------------
create or replace function public.disparar_sincronizacao_atlas()
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_url     text;
  v_segredo text;
begin
  select decrypted_secret into v_url
    from vault.decrypted_secrets where name = 'torre_url_sincronizar_atlas';
  select decrypted_secret into v_segredo
    from vault.decrypted_secrets where name = 'torre_cron_secret';

  if v_url is null or v_segredo is null then
    raise exception 'Vault incompleto: cadastre torre_url_sincronizar_atlas e torre_cron_secret (passo 02, seção 0)';
  end if;

  -- pg_net é assíncrono: a resposta fica em net._http_response por algumas horas.
  -- 60 s de espera: a função pode levar até 2 x 25 s no Atlas.
  return net.http_post(
    url                  := v_url,
    headers              := jsonb_build_object('Content-Type', 'application/json',
                                               'x-cron-secret', v_segredo),
    body                 := '{}'::jsonb,
    timeout_milliseconds := 60000
  );
end;
$$;

revoke all on function public.disparar_sincronizacao_atlas() from public, anon, authenticated;


-- -----------------------------------------------------------------------------
-- 3. Agendamentos
-- -----------------------------------------------------------------------------
-- O pg_cron usa UTC. Rodar de novo com o mesmo nome só atualiza o agendamento.

-- Sincronização com o Atlas a cada 15 minutos (mesmo intervalo do script atual).
-- Para trocar o intervalo, mude o 2º argumento (ex.: '*/10 * * * *') e rode de novo.
select cron.schedule(
  'torre-sincronizar-atlas',
  '*/15 * * * *',
  'select public.disparar_sincronizacao_atlas()'
);

-- Limpeza do histórico 1x por dia, às 06:17 UTC (03:17 em Brasília).
select cron.schedule(
  'torre-limpar-historico',
  '17 6 * * *',
  'select public.limpar_historico()'
);


-- -----------------------------------------------------------------------------
-- 4. Conferir (só leitura)
-- -----------------------------------------------------------------------------
-- Agendamentos:
--   select jobid, jobname, schedule, active from cron.job where jobname like 'torre-%';
-- Últimas execuções do cron:
--   select jobid, status, return_message, start_time
--     from cron.job_run_details
--    where jobid in (select jobid from cron.job where jobname like 'torre-%')
--    order by start_time desc limit 10;
-- Respostas HTTP da função (guardadas pelo pg_net por ~6 horas):
--   select id, status_code, left(content::text, 300) as resposta, created
--     from net._http_response order by created desc limit 10;
-- Últimas sincronizações gravadas:
--   select id, iniciado_em, http_status, recebidos, gravados, sem_placa, erro
--     from public.sincronizacao order by id desc limit 10;
-- Disparar uma sincronização agora, sem esperar o cron:
--   select public.disparar_sincronizacao_atlas();


-- -----------------------------------------------------------------------------
-- 5. Pausar e reativar
-- -----------------------------------------------------------------------------
-- Pausar a sincronização (a planilha continua rodando à parte):
--   select cron.alter_job((select jobid from cron.job where jobname = 'torre-sincronizar-atlas'), active := false);
-- Reativar:
--   select cron.alter_job((select jobid from cron.job where jobname = 'torre-sincronizar-atlas'), active := true);
-- Trocar o intervalo sem recriar:
--   select cron.alter_job((select jobid from cron.job where jobname = 'torre-sincronizar-atlas'), schedule := '*/10 * * * *');
-- Remover de vez:
--   select cron.unschedule('torre-sincronizar-atlas');
