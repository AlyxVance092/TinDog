-- Real-time chat: private Broadcast/typing authorization plus message replication.
-- Apply with the Supabase SQL editor or `supabase db push`.

begin;

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'messages'
  ) then
    alter publication supabase_realtime add table public.messages;
  end if;
end;
$$;

drop policy if exists "tindog_chat_realtime_receive" on realtime.messages;
create policy "tindog_chat_realtime_receive"
on realtime.messages
for select
to authenticated
using (
  extension = 'broadcast'
  and case
    when realtime.topic() ~ '^tindog:chat:[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' then
      private.is_conversation_member(
        split_part(realtime.topic(), ':', 3)::uuid
      )
    else false
  end
);

drop policy if exists "tindog_chat_realtime_send" on realtime.messages;
create policy "tindog_chat_realtime_send"
on realtime.messages
for insert
to authenticated
with check (
  extension = 'broadcast'
  and case
    when realtime.topic() ~ '^tindog:chat:[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' then
      private.is_conversation_member(
        split_part(realtime.topic(), ':', 3)::uuid
      )
    else false
  end
);

commit;
