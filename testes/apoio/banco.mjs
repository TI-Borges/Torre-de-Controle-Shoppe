// Banco de teste: PGlite (Postgres em WebAssembly) imitando o que o Supabase
// tem por padrão: papéis anon/authenticated/service_role, auth.users, auth.uid()
// e os grants automáticos que o Supabase dá às tabelas novas do schema public.
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
  grant usage on schema auth to anon, authenticated, service_role;
  grant execute on function auth.uid() to anon, authenticated, service_role;

  grant usage on schema public to anon, authenticated, service_role;
  alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
  alter default privileges in schema public grant all on sequences to anon, authenticated, service_role;
  alter default privileges in schema public grant all on functions to anon, authenticated, service_role;
`;

export async function criarBanco({ comPasso01 = true } = {}) {
  const db = new PGlite();
  await db.exec(SUPABASE_SIMULADO);
  if (comPasso01) await db.exec(await lerArquivo('supabase/sql/passo01_atlas.sql'));
  return db;
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
