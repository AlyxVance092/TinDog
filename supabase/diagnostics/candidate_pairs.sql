-- Read-only: run as postgres in Supabase SQL Editor.
-- Focused on the Caleb/Papu accounts to show why their dogs do not match.

select
  me.name as my_dog,
  me.id as my_dog_id,
  other_dog.name as other_dog,
  other_dog.id as other_dog_id,
  my_user.display_name as my_account,
  other_user.display_name as other_account,
  me.primary_intention as my_intention,
  me.secondary_intention as my_secondary_intention,
  other_dog.primary_intention as candidate_intention,
  other_dog.secondary_intention as candidate_secondary_intention,
  private.owner_distance_km(me.owner_id, other_dog.owner_id)::integer
    as distance_km,
  coalesce(my_pref.max_distance_km, 25) as my_radius_km,
  coalesce(other_pref.max_distance_km, 25) as other_radius_km,
  pair.o_mode as match_mode,
  case
    when my_user.location is null then 'my_account_missing_location'
    when not my_user.is_active then 'my_account_inactive'
    when me.is_visible is not true then 'my_dog_hidden'
    when other_user.location is null then 'candidate_missing_location'
    when not other_user.is_active then 'candidate_account_inactive'
    when other_dog.is_visible is not true then 'candidate_hidden'
    when other_dog.is_deleted is true then 'candidate_deleted'
    when exists (
      select 1 from public.swipes s
       where s.swiper_dog_id = me.id
         and s.target_dog_id = other_dog.id
    ) then 'already_swiped'
    when exists (
      select 1 from public.breeding_requests r
       where r.requester_dog_id = other_dog.id
         and r.target_dog_id = me.id
         and r.status = 'pending'
         and r.expires_at > now()
    ) then 'incoming_request_pending'
    when pair.o_reason is not null then pair.o_reason
    else 'eligible_for_get_candidates'
  end as reason
from public.dogs me
join public.users my_user on my_user.id = me.owner_id
cross join public.dogs other_dog
join public.users other_user on other_user.id = other_dog.owner_id
left join public.dog_preferences my_pref on my_pref.dog_id = me.id
left join public.dog_preferences other_pref on other_pref.dog_id = other_dog.id
cross join lateral private.pair_check(me.id, other_dog.id) pair
where me.owner_id <> other_dog.owner_id
  and my_user.display_name in ('Caleb', 'Papu')
  and other_user.display_name in ('Caleb', 'Papu')
  and not me.is_deleted
  and not other_dog.is_deleted
order by my_account, my_dog, other_account, other_dog;
