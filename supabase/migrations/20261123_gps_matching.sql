-- Store each authenticated user's private GPS point and expose only rounded
-- distances to visible dogs. Run once in the Supabase SQL Editor.

create table if not exists public.user_locations (
  user_id uuid primary key references auth.users(id) on delete cascade,
  latitude double precision not null check (latitude between -90 and 90),
  longitude double precision not null check (longitude between -180 and 180),
  updated_at timestamptz not null default now()
);

alter table public.user_locations enable row level security;
revoke all on table public.user_locations from public, anon, authenticated;
grant select, insert, update on table public.user_locations to authenticated;

drop policy if exists user_locations_select_own on public.user_locations;
create policy user_locations_select_own on public.user_locations
  for select to authenticated using (user_id = (select auth.uid()));
drop policy if exists user_locations_insert_own on public.user_locations;
create policy user_locations_insert_own on public.user_locations
  for insert to authenticated with check (user_id = (select auth.uid()));
drop policy if exists user_locations_update_own on public.user_locations;
create policy user_locations_update_own on public.user_locations
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

create or replace function public.discover_dog_distances(
  p_radius_km integer default 100
)
returns table (dog_id uuid, distance_km integer)
language sql
stable
security definer
set search_path = pg_catalog
as $$
  with me as (
    select u.user_id, u.latitude, u.longitude
      from public.user_locations as u
     where u.user_id = auth.uid()
       and u.latitude between -90 and 90
       and u.longitude between -180 and 180
  ), distances as (
    select d.id as dog_id,
           6371.0088 * 2 * asin(sqrt(least(1.0, greatest(0.0,
             power(sin(radians(owner_user.latitude - me.latitude) / 2), 2) +
             cos(radians(me.latitude)) * cos(radians(owner_user.latitude)) *
             power(sin(radians(owner_user.longitude - me.longitude) / 2), 2)
           )))) as km
      from public.dogs as d
      join public.user_locations as owner_user on owner_user.user_id = d.owner_id
      cross join me
     where d.owner_id <> me.user_id
       and d.is_visible is true
       and d.is_deleted is false
       and owner_user.latitude between -90 and 90
       and owner_user.longitude between -180 and 180
  )
  select distances.dog_id, ceil(distances.km)::integer as distance_km
    from distances
      where distances.km <= least(100, greatest(1, coalesce(p_radius_km, 100)))
$$;

revoke all on function public.discover_dog_distances(integer) from public, anon;
grant execute on function public.discover_dog_distances(integer) to authenticated;
