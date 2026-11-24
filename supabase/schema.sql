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
create table if not exists invoices (
  id text primary key, number text, client text, client_email text, status text default 'draft',
  currency text, total numeric, issue_date text, due_date text, data jsonb,
  created_at timestamptz default now(), updated_at timestamptz default now()
);
-- Work log: minutes edited, thumbnails and scripts per person (admin only)
create table if not exists work_log (
  id text primary key, period text, work_date text, person text, role text, qty numeric,
  client text, note text, created_at timestamptz default now()
);
alter table settings add column if not exists work_profile jsonb;
-- Editor pay per project: minutes edited, optional special rate, extra for advanced projects (admin only)
create table if not exists project_pay (
  project_id text primary key, minutes numeric, rate numeric, extra numeric, note text,
  updated_at timestamptz default now()
);
-- Client payments per project: done projects are unpaid until marked paid (admin only)
create table if not exists project_billing (
  project_id text primary key, paid boolean default false, paid_at timestamptz, invoice_id text,
  updated_at timestamptz default now()
);
-- Your business details, payment info and saved client emails for invoices (admin only)
alter table settings add column if not exists invoice_profile jsonb;

-- Minutes edited per project (entered by the editor or admin)
alter table projects add column if not exists minutes numeric;
-- When a project was first sent to the client (Client Review or Done): it counts as unpaid from then on
alter table project_billing add column if not exists billable_at timestamptz;
-- What each client pays: per minute or a flat price per video, in US dollars (admin only)
create table if not exists client_rates (
  client text primary key, mode text not null default 'minute' check (mode in ('minute','flat')),
  rate numeric not null check (rate >= 0), updated_at timestamptz default now()
);
-- Safe formats for anything that reaches the screen (blocks code hidden in IDs or statuses)
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'projects_id_safe') then
    alter table projects add constraint projects_id_safe check (id ~ '^[A-Za-z0-9_-]{1,100}$');
  end if;
  if not exists (select 1 from pg_constraint where conname = 'projects_status_known') then
    alter table projects add constraint projects_status_known check (status is null or status in
      ('Assigned','In Progress','In QC','Client Review','Need Revision','Done'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'projects_minutes_range') then
    alter table projects add constraint projects_minutes_range check (minutes is null or (minutes >= 0 and minutes < 100000));
  end if;
end $$;

-- Private tables (no API access at all)
create table if not exists crm_secrets (key text primary key, value text not null);
create table if not exists crm_sessions (
  uid uuid primary key, role text not null, name text, created_at timestamptz default now()
);
create table if not exists crm_login_attempts (id bigint generated always as identity primary key,
  who text not null, at timestamptz default now());
create index if not exists crm_login_attempts_who on crm_login_attempts (who, at);
-- Scrambled passwords live here, never in a table the app can read
create table if not exists crm_passwords (role text not null, name text not null, hash text not null, primary key (role, name));
-- Browsers that have signed in successfully before (used so a lockout can't shut out the real person)
create table if not exists crm_trusted_devices (uid uuid not null, role text not null, name text not null default '', last_ok timestamptz default now(), primary key (uid, role, name));
alter table crm_login_attempts add column if not exists uid uuid;

-- ───────────── Who is signed in ─────────────
-- A login lasts 30 days, and ends at once if the person's account is removed.
create or replace function crm_role() returns text
language sql stable security definer set search_path = public as $$
  select s.role from crm_sessions s
  where s.uid = auth.uid()
    and s.created_at > now() - case when s.role = 'admin' then interval '7 days' else interval '30 days' end
    and (s.role = 'admin'
      or (s.role = 'editor' and exists (select 1 from editor_accounts a where a.name = s.name))
      or (s.role = 'client' and exists (select 1 from client_accounts a where a.name = s.name)))
$$;
create or replace function crm_name() returns text
language sql stable security definer set search_path = public as
$$ select name from crm_sessions where uid = auth.uid() and crm_role() is not null $$;
create or replace function crm_whoami() returns jsonb
language sql stable security definer set search_path = public as
$$ select case when crm_role() is null then null else jsonb_build_object('role', crm_role(), 'name', crm_name()) end $$;

create or replace function crm_login(p_role text, p_name text, p_pass text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_who text := coalesce(p_role, '') || ':' || lower(coalesce(trim(p_name), ''));
  v_name text;
  v_ok boolean := false;
begin
  if auth.uid() is null then raise exception 'Not connected. Refresh the page.'; end if;
  if p_role not in ('admin', 'editor', 'client') or length(coalesce(p_pass, '')) > 200 then return null; end if;
  -- this browser: 5 wrong tries per 15 minutes
  if (select count(*) from crm_login_attempts where uid = auth.uid() and at > now() - interval '15 minutes') >= 5 then
    raise exception 'Too many wrong tries. Wait 15 minutes and try again.';
  end if;
  -- this account from anywhere: 20 per 15 minutes, unless this browser has signed in to it before
  if (select count(*) from crm_login_attempts where who = v_who and at > now() - interval '15 minutes') >= 20
     and not exists (select 1 from crm_trusted_devices t where t.uid = auth.uid() and t.role = p_role
                     and lower(t.name) = lower(coalesce(trim(p_name), '')) and t.last_ok > now() - interval '90 days') then
    raise exception 'Too many wrong tries on this account. Wait 15 minutes and try again.';
  end if;
  if p_role = 'admin' then
    select true into v_ok from crm_secrets where key = 'admin_pass' and value = crypt(p_pass, value);
  else
    select a.name into v_name
      from (select name from editor_accounts where p_role = 'editor' union all select name from client_accounts where p_role = 'client') a
      join crm_passwords pw on pw.role = p_role and pw.name = a.name
      where lower(a.name) = lower(trim(p_name)) and pw.hash = crypt(p_pass, pw.hash)
      limit 1;
    v_ok := v_name is not null;
  end if;
  if not coalesce(v_ok, false) then
    insert into crm_login_attempts (who, uid) values (v_who, auth.uid());
    return null;
  end if;
  delete from crm_login_attempts where (who = v_who and uid = auth.uid()) or at < now() - interval '1 day';
  insert into crm_trusted_devices (uid, role, name, last_ok) values (auth.uid(), p_role, lower(coalesce(trim(p_name), '')), now())
    on conflict (uid, role, name) do update set last_ok = now();
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
  delete from crm_sessions where role = 'admin' and uid <> auth.uid();   -- sign out other admin browsers
end $$;

-- Keep a person's password (and their logins) when the admin renames them
create or replace function crm_rename_login(p_role text, p_old text, p_new text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if crm_role() is distinct from 'admin' then raise exception 'Admins only'; end if;
  delete from crm_passwords where role = p_role and name = p_new and p_new <> p_old;
  update crm_passwords set name = p_new where role = p_role and name = p_old;
  update crm_sessions set name = p_new where role = p_role and name = p_old;
end $$;

-- Settings that editors/clients need: nothing about money, salaries or clients
create or replace function crm_public_settings() returns jsonb
language sql stable security definer set search_path = public as
$$ select case when crm_role() is null then null else '{}'::jsonb end $$;

-- ───────────── Passwords ─────────────
-- Whatever is typed is scrambled into crm_passwords; the account table never keeps it.
create or replace function crm_hash_password() returns trigger
language plpgsql security definer set search_path = public, extensions as $$
declare r text := case tg_table_name when 'editor_accounts' then 'editor' else 'client' end; h text;
begin
  if new.password is not null and new.password <> '' then
    if new.password ~ '^\$2[aby]\$\d\d\$.{53}$' then h := new.password;
    else
      if length(new.password) < 8 then raise exception 'Password must be at least 8 characters'; end if;
      if length(new.password) > 200 then raise exception 'Password is too long'; end if;
      h := crypt(new.password, gen_salt('bf'));
    end if;
    insert into crm_passwords (role, name, hash) values (r, new.name, h)
      on conflict (role, name) do update set hash = excluded.hash;
    -- a new password signs that person out everywhere else
    delete from crm_sessions where role = r and name = new.name and uid is distinct from auth.uid();
  end if;
  new.password := null;
  return new;
end $$;
drop trigger if exists hash_pw on editor_accounts;
create trigger hash_pw before insert or update on editor_accounts for each row execute function crm_hash_password();
drop trigger if exists hash_pw on client_accounts;
create trigger hash_pw before insert or update on client_accounts for each row execute function crm_hash_password();

create or replace function crm_forget_account() returns trigger
language plpgsql security definer set search_path = public as $$
declare r text := case tg_table_name when 'editor_accounts' then 'editor' else 'client' end;
begin
  delete from crm_passwords where role = r and name = old.name;
  delete from crm_sessions where role = r and name = old.name;
  delete from crm_trusted_devices where role = r and name = lower(old.name);
  return old;
end $$;
drop trigger if exists forget_account on editor_accounts;
create trigger forget_account after delete on editor_accounts for each row execute function crm_forget_account();
drop trigger if exists forget_account on client_accounts;
create trigger forget_account after delete on client_accounts for each row execute function crm_forget_account();

-- Move any old-style passwords out of the account tables
insert into crm_passwords (role, name, hash) select 'editor', name, password from editor_accounts where password ~ '^\$2' on conflict do nothing;
insert into crm_passwords (role, name, hash) select 'client', name, password from client_accounts where password ~ '^\$2' on conflict do nothing;
update editor_accounts set password = null where password is not null;
update client_accounts set password = null where password is not null;

-- Teams never store a password
create or replace function crm_no_team_password() returns trigger language plpgsql as
$$ begin new.password := null; return new; end $$;
drop trigger if exists no_team_password on teams;
create trigger no_team_password before insert or update on teams for each row execute function crm_no_team_password();
update teams set password = null where password is not null;

-- ───────────── Projects: money and billing ─────────────
-- Editors/clients can't change money, points, minutes (clients) or who a project belongs to
create or replace function crm_guard_project() returns trigger
language plpgsql set search_path = public as $$
declare r text := crm_role(); n text := crm_name();
begin
  if r = 'admin' then return new; end if;
  if tg_op = 'INSERT' then
    new.revenue := null; new.revenue_gross := null; new.revenue_source := null;
    new.points := null; new.point_calc := null;
    if r = 'editor' then new.editor := n; new.client := null; end if;
    if r = 'client' then new.client := n; new.editor := null; new.minutes := null; end if;
  else
    new.revenue := old.revenue; new.revenue_gross := old.revenue_gross; new.revenue_source := old.revenue_source;
    new.points := old.points; new.point_calc := old.point_calc;
    new.editor := old.editor; new.client := old.client; new.period := old.period;
    if r = 'editor' then new.deadline := old.deadline; end if;
    if r = 'client' then new.minutes := old.minutes; new.status := old.status; end if;
  end if;
  return new;
end $$;
drop trigger if exists guard_project on projects;
create trigger guard_project before insert or update on projects for each row execute function crm_guard_project();

-- Revenue fills in from the client's rate (per minute × minutes, or flat), unless typed in by hand.
-- Runs after guard_project (triggers fire in name order). Paid projects keep their amount.
create or replace function crm_set_revenue() returns trigger
language plpgsql security definer set search_path = public as $$
declare cr record;
begin
  if coalesce(new.revenue_source, '') not in ('', 'auto') then return new; end if;
  if tg_op = 'UPDATE' and exists (select 1 from project_billing b where b.project_id = new.id and b.paid) then return new; end if;
  select * into cr from client_rates where lower(client) = lower(coalesce(new.client, ''));
  if not found then
    if new.revenue_source = 'auto' then new.revenue := null; new.revenue_gross := null; new.revenue_source := null; end if;
    return new;
  end if;
  new.revenue := to_jsonb(case when cr.mode = 'flat' then cr.rate else round(coalesce(new.minutes, 0) * cr.rate, 2) end);
  new.revenue_gross := new.revenue;
  new.revenue_source := 'auto';
  return new;
end $$;
drop trigger if exists set_revenue on projects;
create trigger set_revenue before insert or update on projects for each row execute function crm_set_revenue();

-- First time a video goes to the client (Client Review or Done), it starts counting as unpaid
create or replace function crm_mark_billable() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.status in ('Client Review', 'Done') then
    insert into project_billing (project_id, billable_at) values (new.id, now())
      on conflict (project_id) do update set billable_at = coalesce(project_billing.billable_at, now());
  end if;
  return null;
end $$;
drop trigger if exists mark_billable on projects;
create trigger mark_billable after insert or update of status on projects for each row execute function crm_mark_billable();

-- Admin sets a client's price; unpaid auto-priced projects for that client update straight away
create or replace function crm_set_client_rate(p_client text, p_mode text, p_rate numeric) returns integer
language plpgsql security definer set search_path = public as $$
declare n integer;
begin
  if crm_role() is distinct from 'admin' then raise exception 'Admins only'; end if;
  if coalesce(trim(p_client), '') = '' then raise exception 'Client name missing'; end if;
  if p_rate is null then
    delete from client_rates where lower(client) = lower(trim(p_client));
  else
    if p_mode not in ('minute', 'flat') or p_rate < 0 then raise exception 'Invalid rate'; end if;
    delete from client_rates where lower(client) = lower(trim(p_client)) and client <> trim(p_client);
    insert into client_rates (client, mode, rate, updated_at) values (trim(p_client), p_mode, p_rate, now())
      on conflict (client) do update set mode = excluded.mode, rate = excluded.rate, updated_at = now();
  end if;
  update projects p set updated_at = now()
    where lower(p.client) = lower(trim(p_client)) and coalesce(p.revenue_source, '') in ('', 'auto')
      and not exists (select 1 from project_billing b where b.project_id = p.id and b.paid);
  get diagnostics n = row_count;
  return n;
end $$;

-- ───────────── Safe helpers ─────────────
create or replace function crm_num(t text) returns numeric language plpgsql immutable as $$
begin return nullif(trim(t), '')::numeric; exception when others then return null; end $$;
-- only custom board columns (col_…) are shown to editors and clients
create or replace function crm_safe_custom(j jsonb) returns jsonb language sql immutable as $$
  select coalesce(jsonb_object_agg(k, v), '{}'::jsonb)
  from jsonb_each(case when jsonb_typeof(j) = 'object' then j else '{}'::jsonb end) e(k, v)
  where k ~ '^col_[A-Za-z0-9_]{1,60}$' $$;
create or replace function crm_merge_custom(old_j jsonb, new_j jsonb) returns jsonb language sql immutable as $$
  select (coalesce(old_j, '{}'::jsonb) - coalesce((select array_agg(k) from jsonb_object_keys(coalesce(old_j, '{}'::jsonb)) k where k ~ '^col_'), '{}'::text[]))
         || crm_safe_custom(new_j) $$;

-- ───────────── Access rules ─────────────
do $$
declare t text;
begin
  foreach t in array array['settings','period_settings','columns','projects','teams','individuals',
    'editor_accounts','client_accounts','expenses','leads','project_bin','expense_bin','roster_history','invoices','work_log',
    'project_pay','project_billing','client_rates','crm_secrets','crm_sessions','crm_login_attempts','crm_passwords','crm_trusted_devices'] loop
    execute format('alter table %I enable row level security', t);
    execute format('drop policy if exists admin_all on %I', t);
    execute format('drop policy if exists staff_read on %I', t);
  end loop;
  -- Admin can do everything on the app tables
  foreach t in array array['settings','period_settings','columns','projects','teams','individuals',
    'editor_accounts','client_accounts','expenses','leads','project_bin','expense_bin','roster_history','invoices','work_log',
    'project_pay','project_billing','client_rates'] loop
    execute format($p$create policy admin_all on %I for all to authenticated
      using (crm_role() = 'admin') with check (crm_role() = 'admin')$p$, t);
  end loop;
  -- Editors can read teams (for the leaderboard); editors and clients can read the board layout
  foreach t in array array['teams','individuals','roster_history'] loop
    execute format($p$create policy staff_read on %I for select to authenticated using (crm_role() = 'editor')$p$, t);
  end loop;
  execute $p$create policy staff_read on columns for select to authenticated using (crm_role() in ('editor','client') and not coalesce(admin_only, false))$p$;
end $$;

-- Projects: editors and clients never touch the table directly.
-- They read through functions that leave out money, minutes rates and other people's details,
-- and save through functions that only accept the fields they're allowed to change.
drop policy if exists editor_read on projects;
drop policy if exists editor_write on projects;
drop policy if exists editor_insert on projects;
drop policy if exists client_read on projects;
drop policy if exists client_write on projects;
drop policy if exists client_insert on projects;

create or replace function crm_editor_projects() returns setof jsonb
language sql stable security definer set search_path = public as $$
  -- their own projects: everything they work with (never client, money or points)
  select (to_jsonb(p) - 'client' - 'revenue' - 'revenue_gross' - 'revenue_source' - 'points' - 'point_calc'
          - 'created_by' - 'custom_fields')
         || jsonb_build_object('custom_fields', crm_safe_custom(p.custom_fields),
              'minutes_locked', exists (select 1 from project_billing b where b.project_id = p.id and b.billable_at is not null))
  from projects p where crm_role() = 'editor' and p.editor = crm_name()
  union all
  -- everyone else's: only what the leaderboard and team view need (no titles, notes, links or dates)
  select jsonb_build_object('id', p.id, 'period', p.period, 'editor', p.editor, 'status', p.status, 'minutes', p.minutes)
  from projects p where crm_role() = 'editor' and p.editor is distinct from crm_name() $$;

create or replace function crm_editor_save(p_rows jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare r jsonb; me text := crm_name(); v_id text; v_status text; v_min numeric;
begin
  if crm_role() is distinct from 'editor' then raise exception 'Editors only'; end if;
  if jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) > 200 then raise exception 'Bad request'; end if;
  for r in select * from jsonb_array_elements(p_rows) loop
    v_id := r->>'id';
    if v_id is null or v_id !~ '^[A-Za-z0-9_-]{1,100}$' then continue; end if;
    v_status := case when r->>'status' in ('Assigned','In Progress','In QC','Client Review','Need Revision','Done') then r->>'status' end;
    v_min := crm_num(r->>'minutes');
    if v_min is not null and (v_min < 0 or v_min >= 100000) then v_min := null; end if;
    if exists (select 1 from projects where id = v_id) then
      -- only the fields an editor may change, only on their own projects;
      -- minutes lock once the video has gone to the client
      update projects set
        raw_file      = case when r ? 'raw_file'      then r->'raw_file'      else raw_file end,
        status        = coalesce(v_status, status),
        final_video   = case when r ? 'final_video'   then r->'final_video'   else final_video end,
        frameio       = case when r ? 'frameio'       then r->'frameio'       else frameio end,
        notes         = case when r ? 'notes'         then r->'notes'         else notes end,
        custom_fields = case when r ? 'custom_fields' then crm_merge_custom(custom_fields, r->'custom_fields') else custom_fields end,
        minutes       = case when r ? 'minutes' and not exists (select 1 from project_billing b where b.project_id = v_id and b.billable_at is not null)
                             then v_min else minutes end,
        updated_at    = now()
      where id = v_id and editor = me;
    else
      insert into projects (id, period, raw_file, editor, status, final_video, notes, custom_fields, minutes, created_at, created_by)
      values (v_id, case when r->>'period' ~ '^\d{4}-\d{2}$' then r->>'period' end, r->'raw_file', me,
              coalesce(v_status, 'Assigned'), r->'final_video', r->'notes', crm_safe_custom(r->'custom_fields'), v_min,
              now()::text, 'editor');
    end if;
  end loop;
end $$;

create or replace function crm_client_projects() returns setof jsonb
language sql stable security definer set search_path = public as $$
  select (to_jsonb(p) - 'revenue' - 'revenue_gross' - 'revenue_source' - 'points' - 'point_calc' - 'minutes'
          - 'editor' - 'created_by' - 'custom_fields' - 'final_video')
         || jsonb_build_object('custom_fields', crm_safe_custom(p.custom_fields),
              'final_video', case when p.status in ('Client Review','Need Revision','Done') then p.final_video end)
  from projects p where crm_role() = 'client' and p.client = crm_name() $$;

create or replace function crm_client_save(p_rows jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare r jsonb; me text := crm_name(); v_id text; v_dl text;
begin
  if crm_role() is distinct from 'client' then raise exception 'Clients only'; end if;
  if jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) > 200 then raise exception 'Bad request'; end if;
  for r in select * from jsonb_array_elements(p_rows) loop
    v_id := r->>'id';
    if v_id is null or v_id !~ '^[A-Za-z0-9_-]{1,100}$' then continue; end if;
    v_dl := case when r->>'deadline' ~ '^\d{4}-\d{2}-\d{2}$' then r->>'deadline' end;
    if exists (select 1 from projects where id = v_id) then
      update projects set
        raw_file      = case when r ? 'raw_file' then r->'raw_file' else raw_file end,
        deadline      = case when r ? 'deadline' then v_dl else deadline end,
        notes         = case when r ? 'notes'    then r->'notes'    else notes end,
        custom_fields = case when r ? 'custom_fields' then crm_merge_custom(custom_fields, r->'custom_fields') else custom_fields end,
        updated_at    = now()
      where id = v_id and client = me;
    else
      insert into projects (id, period, raw_file, client, status, deadline, notes, custom_fields, created_at, created_by)
      values (v_id, case when r->>'period' ~ '^\d{4}-\d{2}$' then r->>'period' end, r->'raw_file', me, 'Assigned', v_dl,
              r->'notes', crm_safe_custom(r->'custom_fields'), now()::text, 'client');
    end if;
  end loop;
end $$;

revoke execute on all functions in schema public from public, anon;
grant execute on function crm_role(), crm_name(), crm_whoami(), crm_login(text,text,text), crm_logout(),
  crm_set_admin_password(text), crm_public_settings(), crm_rename_login(text,text,text), crm_set_client_rate(text,text,numeric),
  crm_editor_projects(), crm_editor_save(jsonb), crm_client_projects(), crm_client_save(jsonb) to authenticated;

-- Own login: an editor/client can see their own account name and change their own password
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

-- Table permissions (the rules above then decide which rows each person gets)
grant usage on schema public to authenticated;
grant select, insert, update, delete on settings, period_settings, columns, projects, teams, individuals,
  editor_accounts, client_accounts, expenses, leads, project_bin, expense_bin, roster_history, invoices, work_log,
  project_pay, project_billing, client_rates to authenticated;
revoke all on crm_secrets, crm_sessions, crm_login_attempts, crm_passwords, crm_trusted_devices from authenticated, anon;
-- Logged-out visitors get nothing
revoke all on all tables in schema public from anon;

-- ───────────── Live updates (admin) ─────────────
do $$
declare t text;
begin
  foreach t in array array['projects','columns','expenses','leads','teams','individuals','settings',
    'period_settings','project_bin','expense_bin'] loop
    if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = t) then
      execute format('alter publication supabase_realtime add table %I', t);
    end if;
  end loop;
  -- account tables are not broadcast
  foreach t in array array['editor_accounts','client_accounts'] loop
    if exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = t) then
      execute format('alter publication supabase_realtime drop table %I', t);
    end if;
  end loop;
end $$;
