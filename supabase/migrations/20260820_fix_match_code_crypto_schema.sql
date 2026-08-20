create or replace function public.create_secure_match_code()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_code text;
begin
  perform public.ensure_player_profile(new.customer_id);
  loop
    v_code := upper(encode(extensions.gen_random_bytes(8), 'hex'));
    begin
      insert into public.match_join_codes(booking_id, code_hash, display_code)
      values (new.id, encode(extensions.digest(v_code, 'sha256'), 'hex'), v_code);
      exit;
    exception when unique_violation then
      null;
    end;
  end loop;
  return new;
end;
$$;

revoke all on function public.create_secure_match_code() from public, anon, authenticated;
