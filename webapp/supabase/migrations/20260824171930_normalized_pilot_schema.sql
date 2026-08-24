-- Normalized persistence target for PanelVault's post-pilot migration.
--
-- The Node API remains the only authorization boundary and uses the service
-- role. RLS is still enabled defensively and browser roles receive no grants.
-- The existing panelvault_state document remains the live compatibility store
-- until the dual-write/backfill release is explicitly enabled.

create table if not exists public.panelvault_companies (
  code text primary key,
  name text not null,
  workspace_version bigint not null default 0 check (workspace_version >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.panelvault_users (
  id text primary key,
  company_code text not null references public.panelvault_companies(code) on delete cascade,
  name text not null,
  email text,
  role text not null check (role in ('owner', 'manager', 'staff-manager', 'qa', 'staff')),
  password_salt text not null,
  password_hash text not null,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index if not exists panelvault_users_company_name_key
  on public.panelvault_users (company_code, lower(name));
create unique index if not exists panelvault_users_company_email_key
  on public.panelvault_users (company_code, lower(email)) where email is not null;

create table if not exists public.panelvault_projects (
  id text primary key,
  company_code text not null references public.panelvault_companies(code) on delete cascade,
  revision bigint not null default 1 check (revision > 0),
  name text not null,
  customer text not null,
  site text,
  detail text,
  status text not null,
  color_hex text,
  due_date timestamptz,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index if not exists panelvault_projects_company_name_key
  on public.panelvault_projects (company_code, lower(name));

create table if not exists public.panelvault_boards (
  id text primary key,
  company_code text not null references public.panelvault_companies(code) on delete cascade,
  project_id text references public.panelvault_projects(id) on delete set null,
  assigned_to text references public.panelvault_users(id) on delete set null,
  qa_assigned_to text references public.panelvault_users(id) on delete set null,
  revision bigint not null default 1 check (revision > 0),
  number text not null,
  name text not null,
  customer text not null,
  production_stage text not null default 'design',
  qa_status text not null default 'pending',
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists panelvault_boards_company_updated_idx
  on public.panelvault_boards (company_code, updated_at desc);
create index if not exists panelvault_boards_assigned_idx
  on public.panelvault_boards (company_code, assigned_to) where assigned_to is not null;

create table if not exists public.panelvault_components (
  id text primary key,
  company_code text not null references public.panelvault_companies(code) on delete cascade,
  board_id text references public.panelvault_boards(id) on delete cascade,
  part_id text not null,
  quantity integer not null check (quantity > 0),
  reference text,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists panelvault_components_board_idx on public.panelvault_components (board_id);

create table if not exists public.panelvault_movements (
  id text primary key,
  company_code text not null references public.panelvault_companies(code) on delete cascade,
  user_id text references public.panelvault_users(id) on delete set null,
  board_id text references public.panelvault_boards(id) on delete set null,
  part_id text not null,
  kind text not null check (kind in ('receive', 'consume', 'adjust', 'reserve', 'release')),
  quantity integer not null check (quantity <> 0),
  sequence bigint not null check (sequence > 0),
  reference text,
  device_id text,
  occurred_at timestamptz not null,
  created_at timestamptz not null default now(),
  unique (company_code, sequence)
);
create index if not exists panelvault_movements_part_idx
  on public.panelvault_movements (company_code, part_id, sequence);

create table if not exists public.panelvault_deliveries (
  id text primary key,
  company_code text not null references public.panelvault_companies(code) on delete cascade,
  user_id text references public.panelvault_users(id) on delete set null,
  sequence bigint not null check (sequence > 0),
  note_number text,
  supplier text,
  source text not null,
  device_id text,
  scanned_at timestamptz,
  confirmed_at timestamptz not null,
  uploaded_at timestamptz not null default now(),
  payload jsonb not null default '{}'::jsonb,
  unique (company_code, sequence)
);

create table if not exists public.panelvault_delivery_lines (
  id bigint generated always as identity primary key,
  delivery_id text not null references public.panelvault_deliveries(id) on delete cascade,
  movement_id text references public.panelvault_movements(id) on delete set null,
  part_id text,
  raw_text text,
  quantity integer not null default 0,
  included boolean not null default false
);
create index if not exists panelvault_delivery_lines_delivery_idx
  on public.panelvault_delivery_lines (delivery_id);

create table if not exists public.panelvault_attachments (
  id text primary key,
  company_code text not null references public.panelvault_companies(code) on delete cascade,
  board_id text references public.panelvault_boards(id) on delete cascade,
  delivery_id text references public.panelvault_deliveries(id) on delete cascade,
  storage_key text not null unique,
  kind text not null,
  file_name text not null,
  mime_type text not null,
  size_bytes bigint not null check (size_bytes > 0),
  checksum_sha256 text not null check (checksum_sha256 ~ '^[0-9a-f]{64}$'),
  uploaded_by text references public.panelvault_users(id) on delete set null,
  created_at timestamptz not null default now(),
  constraint panelvault_attachment_owner check ((board_id is null) <> (delivery_id is null))
);

create table if not exists public.panelvault_workspace_changes (
  change_id text primary key,
  company_code text not null references public.panelvault_companies(code) on delete cascade,
  sequence bigint not null check (sequence > 0),
  entity_type text not null check (entity_type in ('project', 'board')),
  entity_id text not null,
  operation text not null check (operation in ('upsert', 'delete')),
  base_revision bigint not null check (base_revision >= 0),
  resulting_revision bigint not null check (resulting_revision > 0),
  payload jsonb,
  applied_at timestamptz not null default now(),
  unique (company_code, sequence)
);

create table if not exists public.panelvault_audit_entries (
  id text primary key,
  company_code text not null references public.panelvault_companies(code) on delete cascade,
  actor_id text references public.panelvault_users(id) on delete set null,
  action text not null,
  entity_type text not null,
  entity_id text,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists panelvault_audit_company_created_idx
  on public.panelvault_audit_entries (company_code, created_at desc);

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'panelvault_companies', 'panelvault_users', 'panelvault_projects',
    'panelvault_boards', 'panelvault_components', 'panelvault_movements',
    'panelvault_deliveries', 'panelvault_delivery_lines', 'panelvault_attachments',
    'panelvault_workspace_changes', 'panelvault_audit_entries'
  ] loop
    execute format('alter table public.%I enable row level security', table_name);
    execute format('revoke all on table public.%I from anon, authenticated', table_name);
    execute format('grant select, insert, update, delete on table public.%I to service_role', table_name);
  end loop;
end $$;

grant usage, select on all sequences in schema public to service_role;
