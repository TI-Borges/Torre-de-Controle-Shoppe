// Banco de teste: PGlite (Postgres em WebAssembly) imitando o Supabase DO SITE:
// papéis anon/authenticated/service_role, auth.users, auth.uid(), auth.jwt(), os
// grants automáticos que o Supabase dá às tabelas novas do schema public, a
// public.is_admin() do site (lê app_metadata.role do JWT: admin ou diretoria) e
// três tabelas do site com RLS e linhas (fichas_viagem, perfis, cadastros_agregados).
import { PGlite } from '@electric-sql/pglite';
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

export const RAIZ = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');

export const lerArquivo = (rel) => readFile(path.join(RAIZ, rel), 'utf8');

const SUPABASE_SIMULADO = `
  set timezone = 'UTC';
  create role anon nologin;
  create role authenticated nologin;
  create role service_role nologin bypassrls;

  create schema auth;
  create table auth.users (
    id uuid primary key,
    aud text,
    role text,
    email text,
    created_at timestamptz default now()
  );
  create function auth.uid() returns uuid language sql stable as $$
    select nullif(coalesce(current_setting('request.jwt.claim.sub', true),
                           current_setting('request.jwt.claims', true)::jsonb ->> 'sub'), '')::uuid
  $$;
  create function auth.jwt() returns jsonb language sql stable as $$
    select coalesce(nullif(current_setting('request.jwt.claim', true), ''),
                    nullif(current_setting('request.jwt.claims', true), ''))::jsonb
  $$;
  grant usage on schema auth to anon, authenticated, service_role;
  grant execute on function auth.uid() to anon, authenticated, service_role;
  grant execute on function auth.jwt() to anon, authenticated, service_role;

  grant usage on schema public to anon, authenticated, service_role;
  alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
  alter default privileges in schema public grant all on sequences to anon, authenticated, service_role;
  alter default privileges in schema public grant all on functions to anon, authenticated, service_role;

  -- Site: a mesma regra da public.is_admin() de produção.
  create function public.is_admin() returns boolean
    language sql stable security definer set search_path = ''
  as $$
    select coalesce((auth.jwt() -> 'app_metadata' ->> 'role') in ('admin', 'diretoria'), false)
  $$;

  -- Site: tabelas de exemplo (cada usuário vê o que é seu; admin vê tudo).
  create table public.perfis (id uuid primary key, nome text, email text, cpf text, role text);
  create table public.fichas_viagem (id bigint generated always as identity primary key, motorista_id uuid, destino text);
  create table public.cadastros_agregados (id bigint generated always as identity primary key, user_id uuid, nome text);
  alter table public.perfis enable row level security;
  alter table public.fichas_viagem enable row level security;
  alter table public.cadastros_agregados enable row level security;
  create policy perfis_ler on public.perfis for select to authenticated
    using (id = (select auth.uid()) or (select public.is_admin()));
  create policy fichas_ler on public.fichas_viagem for select to authenticated
    using (motorista_id = (select auth.uid()) or (select public.is_admin()));
  create policy agregados_ler on public.cadastros_agregados for select to authenticated
    using (user_id = (select auth.uid()) or (select public.is_admin()));
  insert into public.perfis values
    ('bbbbbbbb-0000-4000-8000-000000000001', 'Motorista Site 1', '00000000001@motorista.exemplo.invalid', '00000000001', 'motorista'),
    ('bbbbbbbb-0000-4000-8000-000000000002', 'Admin Site', 'admin@exemplo.invalid', null, 'admin');
  insert into public.fichas_viagem (motorista_id, destino) values ('bbbbbbbb-0000-4000-8000-000000000001', 'CD Teste');
  insert into public.cadastros_agregados (user_id, nome) values ('bbbbbbbb-0000-4000-8000-000000000001', 'Agregado Teste');
`;

export async function criarBanco({ comPasso01 = true } = {}) {
  const db = new PGlite();
  await db.exec(SUPABASE_SIMULADO);
  if (comPasso01) await db.exec(await lerArquivo('supabase/sql/passo01_atlas.sql'));
  return db;
}

// Retrato de tudo o que existe FORA do schema torre: tabelas/views (com grants e
// RLS), colunas, funções (com grants e corpo), policies, gatilhos, schemas,
// default privileges e as linhas das tabelas do site. Serve para provar que os
// arquivos da Torre não criam, alteram nem apagam nada do site.
export async function retratoForaDaTorre(db) {
  const consultas = {
    relacoes: `select n.nspname || '.' || c.relname as nome, c.relkind, c.relacl::text, c.relrowsecurity, c.relforcerowsecurity
                 from pg_class c join pg_namespace n on n.oid = c.relnamespace
                where n.nspname <> 'torre' and n.nspname not like 'pg_toast%' and n.nspname not like 'pg_temp%'
                order by 1`,
    colunas: `select table_schema || '.' || table_name || '.' || column_name as nome, data_type
                from information_schema.columns where table_schema not in ('torre', 'pg_catalog', 'information_schema')
               order by 1`,
    funcoes: `select n.nspname || '.' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' as nome,
                     p.proacl::text, p.prosecdef, md5(p.prosrc) as corpo
                from pg_proc p join pg_namespace n on n.oid = p.pronamespace
               where n.nspname not in ('torre', 'pg_catalog', 'information_schema')
               order by 1`,
    policies: `select n.nspname || '.' || c.relname || '.' || p.polname as nome, p.polroles::text, pg_get_expr(p.polqual, p.polrelid) as regra
                 from pg_policy p join pg_class c on c.oid = p.polrelid join pg_namespace n on n.oid = c.relnamespace
                where n.nspname <> 'torre' order by 1`,
    gatilhos: `select c.relname || '.' || t.tgname as nome from pg_trigger t join pg_class c on c.oid = t.tgrelid
                 join pg_namespace n on n.oid = c.relnamespace where n.nspname <> 'torre' order by 1`,
    schemas: `select nspname, nspacl::text from pg_namespace where nspname <> 'torre' and nspname not like 'pg_%temp%' order by 1`,
    padroes: `select coalesce(n.nspname, '(global)') as schema, d.defaclobjtype, d.defaclacl::text
                from pg_default_acl d left join pg_namespace n on n.oid = d.defaclnamespace
               where coalesce(n.nspname, '') <> 'torre' order by 1, 2`,
    linhas_site: `select (select json_agg(p order by id) from public.perfis p)::text as perfis,
                         (select json_agg(f order by id) from public.fichas_viagem f)::text as fichas,
                         (select json_agg(a order by id) from public.cadastros_agregados a)::text as agregados,
                         (select json_agg(u order by id) from auth.users u)::text as usuarios`,
  };
  const retrato = {};
  for (const [nome, sql] of Object.entries(consultas)) retrato[nome] = (await db.query(sql)).rows;
  return retrato;
}

// Divide o arquivo de conferências nos blocos "-- [Cn] ..." e devolve
// { id, titulo, esperado, sql } de cada um.
export function blocosConferencia(texto) {
  const partes = texto.split(/^(?=-- -+\r?\n-- \[C\d+\])/m).filter((p) => /-- \[C\d+\]/.test(p));
  return partes.map((p) => {
    const [, id, titulo] = p.match(/-- \[(C\d+)\] (.+)/);
    const esperado = p.match(/^-- Esperado: (.+)$/m)[1].trim();
    return { id, titulo: titulo.trim(), esperado, sql: p };
  });
}

// Roda um bloco de conferência e devolve o texto depois de "RESULTADO (nada foi salvo): ".
export async function rodarConferencia(db, bloco) {
  const semRollback = bloco.sql.replace(/\nrollback;\s*$/, '\n');
  try {
    await db.exec(semRollback);
    return { erro: 'o bloco terminou sem RESULTADO' };
  } catch (e) {
    const m = String(e.message).match(/RESULTADO \(nada foi salvo\): ([\s\S]+)$/);
    return m ? { resultado: m[1].trim() } : { erro: e.message };
  } finally {
    await db.exec('rollback; reset role;').catch(() => {});
  }
}
