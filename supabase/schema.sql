-- OPTIONAL standalone schema for a brand-new TinDog Supabase project.
-- Do not run this in a project supplied with an existing schema until those
-- tables have been inspected and the Flutter adapter mapped to them. This
-- script adds tindog_* tables; it does not import or connect existing tables.

create table if not exists public.tindog_profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.tindog_dogs (
  id text primary key default gen_random_uuid()::text,
  owner_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  breed text not null,
  age smallint not null check (age >= 0),
  birth_date date,
  sex text not null check (sex in ('Hembra', 'Macho')),
  location text not null default 'Ciudad de México',
  distance_km integer not null default 1 check (distance_km >= 0),
  compatibility integer not null default 80 check (compatibility between 0 and 100),
  pedigree boolean not null default false,
  pedigree_number text not null default '',
  vaccines jsonb not null default '{}'::jsonb,
  photo_url text not null,
  about text not null default '',
  color text not null default '#FFDCCB',
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.tindog_swipes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  dog_id text not null references public.tindog_dogs(id) on delete cascade,
  liked boolean not null,
  created_at timestamptz not null default now(),
  unique (user_id, dog_id)
);

create table if not exists public.tindog_requests (
  id uuid primary key default gen_random_uuid(),
  from_user_id uuid not null references auth.users(id) on delete cascade,
  from_dog_id text not null references public.tindog_dogs(id),
  to_dog_id text not null references public.tindog_dogs(id),
  message text not null default '',
  status text not null default 'pending'
    check (status in ('pending', 'accepted', 'declined')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (from_dog_id, to_dog_id),
  check (from_dog_id <> to_dog_id)
);

create table if not exists public.tindog_matches (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null unique references public.tindog_requests(id) on delete cascade,
  requester_id uuid not null references auth.users(id) on delete cascade,
  recipient_id uuid not null references auth.users(id) on delete cascade,
  requester_dog_id text not null references public.tindog_dogs(id),
  recipient_dog_id text not null references public.tindog_dogs(id),
  created_at timestamptz not null default now()
);

create table if not exists public.tindog_messages (
  id uuid primary key default gen_random_uuid(),
  match_id uuid not null references public.tindog_matches(id) on delete cascade,
  sender_id uuid not null references auth.users(id) on delete cascade,
  body text not null check (length(body) between 1 and 4000),
  created_at timestamptz not null default now()
);

create index if not exists tindog_dogs_active_created_idx
  on public.tindog_dogs (is_active, created_at desc);
create index if not exists tindog_dogs_owner_idx
  on public.tindog_dogs (owner_id, is_active);
create index if not exists tindog_requests_recipient_idx
  on public.tindog_requests (to_dog_id, status, created_at desc);
create index if not exists tindog_requests_sender_idx
  on public.tindog_requests (from_user_id, created_at desc);
create index if not exists tindog_matches_requester_idx
  on public.tindog_matches (requester_id, created_at desc);
create index if not exists tindog_matches_recipient_idx
  on public.tindog_matches (recipient_id, created_at desc);
create index if not exists tindog_messages_match_created_idx
  on public.tindog_messages (match_id, created_at);

create or replace function public.tindog_handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.tindog_profiles (id, display_name)
  values (
    new.id,
    coalesce(
      nullif(new.raw_user_meta_data ->> 'display_name', ''),
      split_part(coalesce(new.email, ''), '@', 1)
    )
  )
  on conflict (id) do update
    set display_name = excluded.display_name,
        updated_at = now();
  return new;
end;
$$;

revoke all on function public.tindog_handle_new_user() from public, anon, authenticated;
drop trigger if exists tindog_on_auth_user_created on auth.users;
create trigger tindog_on_auth_user_created
  after insert on auth.users
  for each row execute function public.tindog_handle_new_user();

create or replace function public.tindog_accept_request(request_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_request record;
  v_match_id uuid;
begin
  select r.id, r.from_user_id, r.from_dog_id, r.to_dog_id, d.owner_id as recipient_id
    into v_request
    from public.tindog_requests r
    join public.tindog_dogs d on d.id = r.to_dog_id
   where r.id = request_id
     and r.status = 'pending'
     and d.owner_id = auth.uid()
   for update of r;

  if not found then
    raise exception 'La solicitud ya no está disponible.' using errcode = 'P0001';
  end if;

  update public.tindog_requests
     set status = 'accepted', updated_at = now()
   where id = v_request.id;

  insert into public.tindog_matches (
    request_id, requester_id, recipient_id, requester_dog_id, recipient_dog_id
  ) values (
    v_request.id, v_request.from_user_id, v_request.recipient_id,
    v_request.from_dog_id, v_request.to_dog_id
  )
  on conflict (request_id) do nothing
  returning id into v_match_id;

  if v_match_id is null then
    select id into v_match_id
      from public.tindog_matches
     where tindog_matches.request_id = $1;
  end if;

  return v_match_id;
end;
$$;

create or replace function public.tindog_decline_request(request_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.tindog_requests r
     set status = 'declined', updated_at = now()
    from public.tindog_dogs d
   where r.id = request_id
     and r.to_dog_id = d.id
     and d.owner_id = auth.uid()
     and r.status = 'pending';

  if not found then
    raise exception 'La solicitud ya no está disponible.' using errcode = 'P0001';
  end if;
end;
$$;

revoke all on function public.tindog_accept_request(uuid) from public, anon;
revoke all on function public.tindog_decline_request(uuid) from public, anon;
grant execute on function public.tindog_accept_request(uuid) to authenticated;
grant execute on function public.tindog_decline_request(uuid) to authenticated;
grant usage on schema public to authenticated;

alter table public.tindog_profiles enable row level security;
alter table public.tindog_dogs enable row level security;
alter table public.tindog_swipes enable row level security;
alter table public.tindog_requests enable row level security;
alter table public.tindog_matches enable row level security;
alter table public.tindog_messages enable row level security;

revoke all on table public.tindog_profiles, public.tindog_dogs,
  public.tindog_swipes, public.tindog_requests, public.tindog_matches,
  public.tindog_messages from anon, authenticated;

grant select on table public.tindog_profiles to authenticated;
grant update (display_name, updated_at) on table public.tindog_profiles to authenticated;
grant select, insert on table public.tindog_dogs to authenticated;
grant update (
  name, breed, age, birth_date, sex, location, distance_km, compatibility,
  pedigree, pedigree_number, vaccines, photo_url, about, color, is_active,
  updated_at
) on table public.tindog_dogs to authenticated;
grant select, insert, delete on table public.tindog_swipes to authenticated;
grant update (liked) on table public.tindog_swipes to authenticated;
grant select on table public.tindog_requests to authenticated;
grant insert (from_user_id, from_dog_id, to_dog_id, message)
  on table public.tindog_requests to authenticated;
grant update (status, updated_at) on table public.tindog_requests to authenticated;
grant select on table public.tindog_matches to authenticated;
grant select, delete on table public.tindog_messages to authenticated;
grant insert (match_id, sender_id, body)
  on table public.tindog_messages to authenticated;

drop policy if exists tindog_profiles_read_self on public.tindog_profiles;
create policy tindog_profiles_read_self on public.tindog_profiles
  for select to authenticated using (id = (select auth.uid()));
drop policy if exists tindog_profiles_update_self on public.tindog_profiles;
create policy tindog_profiles_update_self on public.tindog_profiles
  for update to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

drop policy if exists tindog_dogs_read_active on public.tindog_dogs;
create policy tindog_dogs_read_active on public.tindog_dogs
  for select to authenticated using (
    is_active
    or owner_id = (select auth.uid())
    or exists (
      select 1 from public.tindog_matches m
       where (m.requester_id = (select auth.uid()) and m.recipient_dog_id = tindog_dogs.id)
          or (m.recipient_id = (select auth.uid()) and m.requester_dog_id = tindog_dogs.id)
    )
  );
drop policy if exists tindog_dogs_insert_self on public.tindog_dogs;
create policy tindog_dogs_insert_self on public.tindog_dogs
  for insert to authenticated with check (owner_id = (select auth.uid()));
drop policy if exists tindog_dogs_update_self on public.tindog_dogs;
create policy tindog_dogs_update_self on public.tindog_dogs
  for update to authenticated
  using (owner_id = (select auth.uid()))
  with check (owner_id = (select auth.uid()));

drop policy if exists tindog_swipes_read_self on public.tindog_swipes;
create policy tindog_swipes_read_self on public.tindog_swipes
  for select to authenticated using (user_id = (select auth.uid()));
drop policy if exists tindog_swipes_insert_self on public.tindog_swipes;
create policy tindog_swipes_insert_self on public.tindog_swipes
  for insert to authenticated with check (user_id = (select auth.uid()));
drop policy if exists tindog_swipes_update_self on public.tindog_swipes;
create policy tindog_swipes_update_self on public.tindog_swipes
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
drop policy if exists tindog_swipes_delete_self on public.tindog_swipes;
create policy tindog_swipes_delete_self on public.tindog_swipes
  for delete to authenticated using (user_id = (select auth.uid()));

drop policy if exists tindog_requests_read_participant on public.tindog_requests;
create policy tindog_requests_read_participant on public.tindog_requests
  for select to authenticated using (
    from_user_id = (select auth.uid())
    or exists (
      select 1 from public.tindog_dogs d
       where d.id = to_dog_id and d.owner_id = (select auth.uid())
    )
  );
drop policy if exists tindog_requests_insert_owner on public.tindog_requests;
create policy tindog_requests_insert_owner on public.tindog_requests
  for insert to authenticated with check (
    from_user_id = (select auth.uid())
    and exists (
      select 1 from public.tindog_dogs d
       where d.id = from_dog_id and d.owner_id = (select auth.uid()) and d.is_active
    )
    and exists (
      select 1 from public.tindog_dogs d
       where d.id = to_dog_id and d.is_active and d.owner_id <> (select auth.uid())
    )
  );
drop policy if exists tindog_requests_resend_declined on public.tindog_requests;
create policy tindog_requests_resend_declined on public.tindog_requests
  for update to authenticated
  using (from_user_id = (select auth.uid()) and status = 'declined')
  with check (from_user_id = (select auth.uid()) and status = 'pending');

drop policy if exists tindog_matches_read_participant on public.tindog_matches;
create policy tindog_matches_read_participant on public.tindog_matches
  for select to authenticated using (
    requester_id = (select auth.uid()) or recipient_id = (select auth.uid())
  );

drop policy if exists tindog_messages_read_match on public.tindog_messages;
create policy tindog_messages_read_match on public.tindog_messages
  for select to authenticated using (
    exists (
      select 1 from public.tindog_matches m
       where m.id = match_id
         and (m.requester_id = (select auth.uid()) or m.recipient_id = (select auth.uid()))
    )
  );
drop policy if exists tindog_messages_insert_match on public.tindog_messages;
create policy tindog_messages_insert_match on public.tindog_messages
  for insert to authenticated with check (
    sender_id = (select auth.uid())
    and exists (
      select 1 from public.tindog_matches m
       where m.id = match_id
         and (m.requester_id = (select auth.uid()) or m.recipient_id = (select auth.uid()))
    )
  );
drop policy if exists tindog_messages_delete_own on public.tindog_messages;
create policy tindog_messages_delete_own on public.tindog_messages
  for delete to authenticated using (
    sender_id = (select auth.uid())
    and exists (
      select 1 from public.tindog_matches m
       where m.id = match_id
         and (m.requester_id = (select auth.uid()) or m.recipient_id = (select auth.uid()))
    )
  );

-- Public reads let other signed-in users see dog photos. Upload, replacement,
-- and deletion still require the authenticated owner's folder.
insert into storage.buckets (id, name, public)
values ('tindog-dog-photos', 'tindog-dog-photos', true)
on conflict (id) do update set public = true;

drop policy if exists tindog_photo_owner_read on storage.objects;
create policy tindog_photo_owner_read on storage.objects
  for select to authenticated
  using (
    bucket_id = 'tindog-dog-photos'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );
drop policy if exists tindog_photo_owner_insert on storage.objects;
create policy tindog_photo_owner_insert on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'tindog-dog-photos'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );
drop policy if exists tindog_photo_owner_update on storage.objects;
create policy tindog_photo_owner_update on storage.objects
  for update to authenticated
  using (
    bucket_id = 'tindog-dog-photos'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  )
  with check (
    bucket_id = 'tindog-dog-photos'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );
drop policy if exists tindog_photo_owner_delete on storage.objects;
create policy tindog_photo_owner_delete on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'tindog-dog-photos'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (
       select 1 from pg_publication_tables
        where pubname = 'supabase_realtime'
          and schemaname = 'public'
          and tablename = 'tindog_messages'
     ) then
    execute 'alter publication supabase_realtime add table public.tindog_messages';
  end if;
end;
$$;

notify pgrst, 'reload schema';
