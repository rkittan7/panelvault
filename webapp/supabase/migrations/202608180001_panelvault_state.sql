-- PanelVault's first Supabase persistence boundary.
-- The existing API remains the authorization boundary, so only the server's
-- service-role key may access this private state table.

create table if not exists public.panelvault_state (
  id text primary key,
  state jsonb not null default '{"companies": {}}'::jsonb,
  version bigint not null default 1,
  updated_at timestamptz not null default now(),
  constraint panelvault_state_primary_row check (id = 'primary'),
  constraint panelvault_state_object check (jsonb_typeof(state) = 'object')
);

alter table public.panelvault_state enable row level security;
revoke all on table public.panelvault_state from anon, authenticated;

create or replace function public.panelvault_state_touch_updated_at()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists panelvault_state_touch_updated_at on public.panelvault_state;
create trigger panelvault_state_touch_updated_at
before update on public.panelvault_state
for each row execute function public.panelvault_state_touch_updated_at();

insert into public.panelvault_state (id)
values ('primary')
on conflict (id) do nothing;

create or replace function public.panelvault_save_state(expected_version bigint, new_state jsonb)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  next_version bigint;
begin
  if jsonb_typeof(new_state) <> 'object' then
    raise exception 'PanelVault state must be a JSON object' using errcode = '22023';
  end if;

  update public.panelvault_state
  set state = new_state, version = version + 1
  where id = 'primary' and version = expected_version
  returning version into next_version;

  if next_version is null then
    raise exception 'PanelVault state changed in another server instance; restart this instance'
      using errcode = '40001';
  end if;
  return next_version;
end;
$$;

revoke all on function public.panelvault_save_state(bigint, jsonb) from public, anon, authenticated;
grant execute on function public.panelvault_save_state(bigint, jsonb) to service_role;
