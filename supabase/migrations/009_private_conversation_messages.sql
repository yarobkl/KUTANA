-- Apply ONLY to the isolated KUTANA project after migrations 001..008.
-- Direct user inserts are removed. Only an authenticated participant can post
-- via this server-side RPC, which supplies sender_id from auth.uid().
revoke insert on public.messages from authenticated;

create or replace function public.send_conversation_message(p_conversation uuid, p_body text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_id uuid; v_user uuid := auth.uid(); v_text text := btrim(p_body);
begin
  if v_user is null then
    raise exception 'Not authenticated' using errcode='42501';
  end if;
  if v_text is null or char_length(v_text) not between 1 and 4000 then
    raise exception 'Invalid message body' using errcode='22023';
  end if;
  if not exists (
    select 1 from public.conversations c
    where c.id = p_conversation and v_user in (c.participant_a, c.participant_b)
  ) then
    raise exception 'Conversation unavailable' using errcode='42501';
  end if;
  insert into public.messages(conversation_id, sender_id, body)
    values(p_conversation, v_user, v_text)
    returning id into v_id;
  return v_id;
end; $$;

revoke all on function public.send_conversation_message(uuid,text) from public, anon;
grant execute on function public.send_conversation_message(uuid,text) to authenticated;
