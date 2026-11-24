-- Agency OS — database setup
-- Run once in Supabase (SQL Editor → New query → paste → Run). Safe to re-run.
--
-- How access works:
--   * Every browser signs in anonymously, then proves who it is with crm_login(role, name, password).
--   * Passwords are stored scrambled (bcrypt) and checked inside the database.
--   * Admin: everything. Editors: the project board, teams, their own login.
--   * Clients: only their own projects. Finance, leads, salaries and logins are admin-only.

create extension if not exists pgcrypto with schema extensions;

-- ───────────── Tables ─────────────
create table if not exists settings (
  id text primary key default 'main',
  split jsonb, point_tiers jsonb, rates jsonb, last_rollover_for text,
  priority_clients jsonb, default_salaries jsonb,
  updated_at timestamptz default now()
);
insert into settings (id) values ('main') on conflict do nothing;

create table if not exists period_settings (
  period text primary key, month_rate jsonb, taka_revenue jsonb, profit_override jsonb,
  profit_note jsonb, notes jsonb, updated_at timestamptz default now()
);
create table if not exists columns (
  id text primary key, label text, type text, admin_only boolean, locked boolean,
  editor_editable boolean, sort_order int, updated_at timestamptz default now()
);
create table if not exists projects (
  id text primary key, period text, raw_file jsonb, editor text, client text,
  revenue jsonb, revenue_gross jsonb, revenue_source text, points jsonb, point_calc jsonb,
  status text, deadline text, frameio jsonb, final_video jsonb, notes jsonb, rolled_from text,
  created_at text, created_by text, custom_fields jsonb, updated_at timestamptz default now()
);
create table if not exists teams (
  id text primary key, name text, leader text, password text, members jsonb,
  sort_order int, updated_at timestamptz default now()
);
create table if not exists individuals (name text primary key, sort_order int);
create table if not exists editor_accounts (name text primary key, password text);
create table if not exists client_accounts (name text primary key, password text, columns jsonb);
create table if not exists expenses (
  id text primary key, period text, name text, usd jsonb, taka jsonb, bonus jsonb, notes jsonb,
  type text, salary_kind text, created_at text, updated_at timestamptz default now()
);
create table if not exists leads (
  id text primary key, name text, contact text, source text, stage text, next_follow_up text,
  notes jsonb, follow_up_count jsonb, created_at text, last_touch text
);
create table if not exists project_bin (id text primary key, project_data jsonb, deleted_at text, deleted_by text);
create table if not exists expense_bin (id text primary key, expense_data jsonb, period text, deleted_at text);
create table if not exists roster_history (period text primary key, teams jsonb, individuals jsonb, snapshot_at text);

-- Private tables (no API access at all)
create table if not exists crm_secrets (key text primary key, value text not null);
create table if not exists crm_sessions (
  uid uuid primary key, role text not null, name text, created_at timestamptz default now()
);
create table if not exists crm_login_attempts (id bigint generated always as identity primary key,
  who text not null, at timestamptz default now());
create index if not exists crm_login_attempts_who on crm_login_attempts (who, at);

-- ───────────── Who is signed in ─────────────
create or replace function crm_role() returns text
language sql stable security definer set search_path = public as
$$ select role from crm_sessions where uid = auth.uid() $$;

create or replace function crm_name() returns text
language sql stable security definer set search_path = public as
$$ select name from crm_sessions where uid = auth.uid() $$;

create or replace function crm_whoami() returns jsonb
language sql stable security definer set search_path = public as
$$ select jsonb_build_object('role', role, 'name', name) from crm_sessions where uid = auth.uid() $$;

create or replace function crm_login(p_role text, p_name text, p_pass text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_who text := p_role || ':' || lower(coalesce(trim(p_name), ''));
  v_name text;
  v_ok boolean := false;
begin
  if auth.uid() is null then raise exception 'Not connected. Refresh the page.'; end if;
  if (select count(*) from crm_login_attempts where who = v_who and at > now() - interval '15 minutes') >= 10 then
    raise exception 'Too many wrong tries. Wait 15 minutes and try again.';
  end if;

  if p_role = 'admin' then
    select true into v_ok from crm_secrets where key = 'admin_pass' and value = crypt(p_pass, value);
  elsif p_role = 'editor' then
    select name into v_name from editor_accounts
      where lower(name) = lower(trim(p_name)) and password = crypt(p_pass, password);
    v_ok := v_name is not null;
  elsif p_role = 'client' then
    select name into v_name from client_accounts
      where lower(name) = lower(trim(p_name)) and password = crypt(p_pass, password);
    v_ok := v_name is not null;
  end if;

  if not coalesce(v_ok, false) then
    insert into crm_login_attempts (who) values (v_who);
    return null;
  end if;

  delete from crm_login_attempts where who = v_who or at < now() - interval '1 day';
  insert into crm_sessions (uid, role, name) values (auth.uid(), p_role, v_name)
    on conflict (uid) do update set role = excluded.role, name = excluded.name, created_at = now();
  return jsonb_build_object('role', p_role, 'name', v_name, 'mode', 'full');
end $$;

create or replace function crm_logout() returns void
language sql security definer set search_path = public as
$$ delete from crm_sessions where uid = auth.uid() $$;

create or replace function crm_set_admin_password(p_new text) returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  if crm_role() is distinct from 'admin' then raise exception 'Admins only'; end if;
  if length(coalesce(p_new, '')) < 8 then raise exception 'Use at least 8 characters'; end if;
  update crm_secrets set value = crypt(p_new, gen_salt('bf')) where key = 'admin_pass';
  -- sign out every other admin browser
  delete from crm_sessions where role = 'admin' and uid <> auth.uid();
end $$;

-- Settings that editors/clients need (no money, no salaries)
create or replace function crm_public_settings() returns jsonb
language sql stable security definer set search_path = public as
$$ select case when crm_role() is null then null
   else jsonb_build_object('point_tiers', point_tiers, 'priority_clients', priority_clients) end
   from settings where id = 'main' $$;

revoke execute on function crm_role(), crm_name(), crm_whoami(), crm_login(text,text,text), crm_logout(),
  crm_set_admin_password(text), crm_public_settings() from public, anon;
grant execute on function crm_role(), crm_name(), crm_whoami(), crm_login(text,text,text), crm_logout(),
  crm_set_admin_password(text), crm_public_settings() to authenticated;

-- ───────────── Scramble passwords on save ─────────────
create or replace function crm_hash_password() returns trigger
language plpgsql set search_path = public, extensions as $$
begin
  if new.password is null or new.password = '' then
    -- blank means "keep the current password" (a new account without one can't log in)
    if tg_op = 'UPDATE' then new.password := old.password; else new.password := null; end if;
  elsif (tg_op = 'UPDATE' and new.password = old.password) or new.password ~ '^\$2[aby]\$\d\d\$.{53}$' then
    null; -- unchanged, or already scrambled (an upsert passes through the insert step first)
  else
    if length(new.password) < 3 then raise exception 'Password must be at least 3 characters'; end if;
    new.password := crypt(new.password, gen_salt('bf'));
  end if;
  return new;
end $$;
drop trigger if exists hash_pw on editor_accounts;
create trigger hash_pw before insert or update on editor_accounts for each row execute function crm_hash_password();
drop trigger if exists hash_pw on client_accounts;
create trigger hash_pw before insert or update on client_accounts for each row execute function crm_hash_password();

-- Editors/clients can't change money, points or who a project belongs to
create or replace function crm_guard_project() returns trigger
language plpgsql set search_path = public as $$
declare r text := crm_role(); n text := crm_name();
begin
  if r = 'admin' then return new; end if;
  if tg_op = 'INSERT' then
    new.revenue := null; new.revenue_gross := null; new.revenue_source := null;
    new.points := null; new.point_calc := null;
    if r = 'editor' then new.editor := n; end if;
    if r = 'client' then new.client := n; new.editor := null; end if;
  else
    new.revenue := old.revenue; new.revenue_gross := old.revenue_gross; new.revenue_source := old.revenue_source;
    new.points := old.points; new.point_calc := old.point_calc;
    new.editor := old.editor; new.client := old.client; new.period := old.period;
    if r = 'editor' then new.deadline := old.deadline; end if;
  end if;
  return new;
end $$;
drop trigger if exists guard_project on projects;
create trigger guard_project before insert or update on projects for each row execute function crm_guard_project();

-- ───────────── Access rules ─────────────
do $$
declare t text;
begin
  foreach t in array array['settings','period_settings','columns','projects','teams','individuals',
    'editor_accounts','client_accounts','expenses','leads','project_bin','expense_bin','roster_history',
    'crm_secrets','crm_sessions','crm_login_attempts'] loop
    execute format('alter table %I enable row level security', t);
    execute format('drop policy if exists admin_all on %I', t);
  end loop;
  -- Admin can do everything on the app tables
  foreach t in array array['settings','period_settings','columns','projects','teams','individuals',
    'editor_accounts','client_accounts','expenses','leads','project_bin','expense_bin','roster_history'] loop
    execute format($p$create policy admin_all on %I for all to authenticated
      using (crm_role() = 'admin') with check (crm_role() = 'admin')$p$, t);
  end loop;
  -- Everyone signed in can read the board layout and teams
  foreach t in array array['columns','teams','individuals','roster_history'] loop
    execute format('drop policy if exists staff_read on %I', t);
    execute format($p$create policy staff_read on %I for select to authenticated
      using (crm_role() in ('editor','client'))$p$, t);
  end loop;
end $$;

-- Projects: editors see all (leaderboard), edit their own; clients see/edit only theirs
drop policy if exists editor_read on projects;
create policy editor_read on projects for select to authenticated using (crm_role() = 'editor');
drop policy if exists editor_write on projects;
create policy editor_write on projects for update to authenticated
  using (crm_role() = 'editor' and editor = crm_name()) with check (crm_role() = 'editor' and editor = crm_name());
drop policy if exists editor_insert on projects;
create policy editor_insert on projects for insert to authenticated
  with check (crm_role() = 'editor' and editor = crm_name());
drop policy if exists client_read on projects;
create policy client_read on projects for select to authenticated
  using (crm_role() = 'client' and client = crm_name());
drop policy if exists client_write on projects;
create policy client_write on projects for update to authenticated
  using (crm_role() = 'client' and client = crm_name()) with check (crm_role() = 'client' and client = crm_name());
drop policy if exists client_insert on projects;
create policy client_insert on projects for insert to authenticated
  with check (crm_role() = 'client' and client = crm_name());

-- Own login: an editor/client can see and change only their own account row
do $$
declare t text; r text;
begin
  foreach t in array array['editor_accounts','client_accounts'] loop
    r := case t when 'editor_accounts' then 'editor' else 'client' end;
    execute format('drop policy if exists own_account on %I', t);
    execute format('drop policy if exists own_read on %I', t);
    execute format('drop policy if exists own_insert on %I', t);
    execute format('drop policy if exists own_update on %I', t);
    execute format($p$create policy own_read on %I for select to authenticated
      using (crm_role() = %L and name = crm_name())$p$, t, r);
    execute format($p$create policy own_insert on %I for insert to authenticated
      with check (crm_role() = %L and name = crm_name())$p$, t, r);
    execute format($p$create policy own_update on %I for update to authenticated
      using (crm_role() = %L and name = crm_name()) with check (crm_role() = %L and name = crm_name())$p$, t, r, r);
  end loop;
end $$;

-- Logged-out visitors get nothing
revoke all on all tables in schema public from anon;

-- ───────────── Live updates ─────────────
do $$
declare t text;
begin
  foreach t in array array['projects','columns','expenses','leads','teams','individuals','settings',
    'period_settings','editor_accounts','client_accounts','project_bin','expense_bin'] loop
    if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = t) then
      execute format('alter publication supabase_realtime add table %I', t);
    end if;
  end loop;
end $$;
