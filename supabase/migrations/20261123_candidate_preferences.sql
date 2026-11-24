-- Restore owner access to per-dog search preferences and remove the retired
-- pedigree-only filter. Run once in the Supabase SQL Editor.

begin;

alter table public.dog_preferences enable row level security;
grant select, insert, update on table public.dog_preferences to authenticated;

drop policy if exists dog_preferences_select_own on public.dog_preferences;
create policy dog_preferences_select_own
  on public.dog_preferences
  for select to authenticated
  using (private.owns_dog(dog_id));

drop policy if exists dog_preferences_insert_own on public.dog_preferences;
create policy dog_preferences_insert_own
  on public.dog_preferences
  for insert to authenticated
  with check (private.owns_dog(dog_id));

drop policy if exists dog_preferences_update_own on public.dog_preferences;
create policy dog_preferences_update_own
  on public.dog_preferences
  for update to authenticated
  using (private.owns_dog(dog_id))
  with check (private.owns_dog(dog_id));

update public.dog_preferences
   set only_pedigree = false
 where only_pedigree is distinct from false;

commit;
