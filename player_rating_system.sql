create table public.player_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null check (char_length(display_name) between 2 and 80),
  position text not null default 'غير محدد' check (position in ('حارس','دفاع','وسط','مهاجم','غير محدد')),
  area text not null default 'بغداد' check (char_length(area) between 2 and 80),
  avatar_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.player_profiles enable row level security;
revoke all on public.player_profiles from anon, authenticated;
grant select on public.player_profiles to anon, authenticated;
grant insert, update (display_name, position, area, avatar_url) on public.player_profiles to authenticated;
create policy "public player profiles" on public.player_profiles for select using (true);
create policy "players create own profile" on public.player_profiles for insert to authenticated with check ((select auth.uid()) = user_id);
create policy "players update own profile" on public.player_profiles for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);

alter table public.stadium_bookings add column join_code text;
update public.stadium_bookings set join_code = upper(substr(md5(id::text || created_at::text || random()::text),1,8)) where join_code is null;
alter table public.stadium_bookings alter column join_code set not null;
alter table public.stadium_bookings add constraint stadium_bookings_join_code_key unique (join_code);

create table public.match_participants (
  booking_id bigint not null references public.stadium_bookings(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  team text not null check (team in ('home','away')),
  joined_at timestamptz not null default now(),
  primary key (booking_id, user_id)
);

create table public.player_ratings (
  id bigint generated always as identity primary key,
  booking_id bigint not null references public.stadium_bookings(id) on delete cascade,
  rater_id uuid not null references auth.users(id) on delete cascade,
  rated_user_id uuid not null references auth.users(id) on delete cascade,
  performance smallint not null check (performance between 1 and 10),
  teamwork smallint not null check (teamwork between 1 and 10),
  sportsmanship smallint not null check (sportsmanship between 1 and 10),
  comment text check (comment is null or char_length(comment) <= 300),
  created_at timestamptz not null default now(),
  unique (booking_id, rater_id, rated_user_id),
  check (rater_id <> rated_user_id)
);

alter table public.match_participants enable row level security;
alter table public.player_ratings enable row level security;
revoke all on public.match_participants, public.player_ratings from anon, authenticated;

create index match_participants_user_idx on public.match_participants(user_id, booking_id);
create index player_ratings_rated_month_idx on public.player_ratings(rated_user_id, created_at desc);
create index player_ratings_booking_idx on public.player_ratings(booking_id);

create or replace function public.ensure_player_profile(p_user_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare u auth.users%rowtype;
begin
  select * into u from auth.users where id = p_user_id;
  if not found then raise exception 'الحساب غير موجود'; end if;
  insert into public.player_profiles(user_id, display_name, avatar_url)
  values (u.id, left(coalesce(nullif(u.raw_user_meta_data->>'full_name',''), nullif(u.raw_user_meta_data->>'name',''), nullif(split_part(u.email,'@',1),''), nullif(u.phone,''), 'لاعب ملعبنا'),80), u.raw_user_meta_data->>'avatar_url')
  on conflict (user_id) do nothing;
end $$;
revoke all on function public.ensure_player_profile(uuid) from public, anon, authenticated;

create or replace function public.on_official_booking_create()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.join_code is null then
    new.join_code := upper(substr(md5(gen_random_uuid()::text || clock_timestamp()::text),1,8));
  end if;
  perform public.ensure_player_profile(new.customer_id);
  return new;
end $$;

create trigger prepare_official_match before insert on public.stadium_bookings
for each row execute function public.on_official_booking_create();

create or replace function public.add_booking_organizer_as_player()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.match_participants(booking_id,user_id,team) values(new.id,new.customer_id,'home') on conflict do nothing;
  return new;
end $$;
create trigger add_booking_organizer after insert on public.stadium_bookings
for each row execute function public.add_booking_organizer_as_player();

insert into public.player_profiles(user_id,display_name,avatar_url)
select u.id,left(coalesce(nullif(u.raw_user_meta_data->>'full_name',''),nullif(u.raw_user_meta_data->>'name',''),nullif(split_part(u.email,'@',1),''),nullif(u.phone,''),'لاعب ملعبنا'),80),u.raw_user_meta_data->>'avatar_url'
from auth.users u join public.stadium_bookings b on b.customer_id=u.id on conflict do nothing;
insert into public.match_participants(booking_id,user_id,team)
select id,customer_id,'home' from public.stadium_bookings on conflict do nothing;

create or replace function public.join_match_by_code(p_code text, p_team text default 'away')
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := auth.uid(); v_booking public.stadium_bookings%rowtype;
begin
  if v_uid is null then raise exception 'يجب تسجيل الدخول'; end if;
  if p_team not in ('home','away') then raise exception 'الفريق غير صحيح'; end if;
  select * into v_booking from public.stadium_bookings where join_code=upper(trim(p_code)) and status='confirmed';
  if not found then raise exception 'رمز المباراة غير صحيح'; end if;
  perform public.ensure_player_profile(v_uid);
  insert into public.match_participants(booking_id,user_id,team) values(v_booking.id,v_uid,p_team)
  on conflict (booking_id,user_id) do update set team=excluded.team;
  return jsonb_build_object('ok',true,'booking_id',v_booking.id);
end $$;

create or replace function public.submit_player_rating(p_booking_id bigint,p_rated_user_id uuid,p_performance smallint,p_teamwork smallint,p_sportsmanship smallint,p_comment text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := auth.uid(); v_match_time timestamp;
begin
  if v_uid is null then raise exception 'يجب تسجيل الدخول'; end if;
  if v_uid=p_rated_user_id then raise exception 'لا يمكنك تقييم نفسك'; end if;
  if p_performance not between 1 and 10 or p_teamwork not between 1 and 10 or p_sportsmanship not between 1 and 10 then raise exception 'التقييم يجب أن يكون من 1 إلى 10'; end if;
  if length(coalesce(p_comment,''))>300 then raise exception 'الملاحظة طويلة جدًا'; end if;
  select s.slot_date+s.start_time+(case when s.start_time<time '03:00' then interval '1 day' else interval '0' end)
  into v_match_time from public.stadium_bookings b join public.stadium_time_slots s on s.id=b.slot_id
  where b.id=p_booking_id and b.status='confirmed';
  if v_match_time is null then raise exception 'المباراة غير موجودة'; end if;
  if v_match_time+interval '1 hour'>timezone('Asia/Baghdad',now()) then raise exception 'يمكن التقييم بعد انتهاء المباراة'; end if;
  if v_match_time<timezone('Asia/Baghdad',now())-interval '30 days' then raise exception 'انتهت مدة التقييم'; end if;
  if not exists(select 1 from public.match_participants where booking_id=p_booking_id and user_id=v_uid)
     or not exists(select 1 from public.match_participants where booking_id=p_booking_id and user_id=p_rated_user_id) then
    raise exception 'التقييم متاح فقط للمشاركين في المباراة';
  end if;
  insert into public.player_ratings(booking_id,rater_id,rated_user_id,performance,teamwork,sportsmanship,comment)
  values(p_booking_id,v_uid,p_rated_user_id,p_performance,p_teamwork,p_sportsmanship,nullif(trim(p_comment),''));
  return jsonb_build_object('ok',true);
exception when unique_violation then raise exception 'سبق أن قيّمت هذا اللاعب في هذه المباراة';
end $$;

create or replace function public.get_my_rateable_players()
returns table(booking_id bigint,match_label text,rated_user_id uuid,display_name text,player_position text)
language sql security definer set search_path = '' stable as $$
  select b.id, st.name||' · '||to_char(s.slot_date,'YYYY-MM-DD')||' '||to_char(s.start_time,'HH24:MI'), p.user_id, pp.display_name, pp.position
  from public.match_participants me
  join public.stadium_bookings b on b.id=me.booking_id and b.status='confirmed'
  join public.stadium_time_slots s on s.id=b.slot_id
  join public.partner_stadiums st on st.id=s.stadium_id
  join public.match_participants p on p.booking_id=b.id and p.user_id<>auth.uid()
  join public.player_profiles pp on pp.user_id=p.user_id
  where me.user_id=auth.uid()
    and s.slot_date+s.start_time+(case when s.start_time<time '03:00' then interval '1 day' else interval '0' end)+interval '1 hour'<=timezone('Asia/Baghdad',now())
    and s.slot_date+s.start_time+(case when s.start_time<time '03:00' then interval '1 day' else interval '0' end)>=timezone('Asia/Baghdad',now())-interval '30 days'
    and not exists(select 1 from public.player_ratings r where r.booking_id=b.id and r.rater_id=auth.uid() and r.rated_user_id=p.user_id)
  order by s.slot_date desc,s.start_time desc;
$$;

create or replace function public.get_monthly_leaderboard(p_month date default date_trunc('month',current_date)::date)
returns table(user_id uuid,display_name text,player_position text,area text,average_rating numeric,matches bigint,rating_count bigint,points bigint)
language sql security definer set search_path = '' stable as $$
  select pp.user_id,pp.display_name,pp.position,pp.area,
    round(avg((r.performance+r.teamwork+r.sportsmanship)/3.0),1),count(distinct r.booking_id),count(r.id),
    round(avg((r.performance+r.teamwork+r.sportsmanship)/3.0)*100+count(distinct r.booking_id)*10)::bigint
  from public.player_ratings r
  join public.player_profiles pp on pp.user_id=r.rated_user_id
  join public.stadium_bookings b on b.id=r.booking_id and b.status='confirmed'
  join public.stadium_time_slots s on s.id=b.slot_id
  where s.slot_date>=date_trunc('month',p_month)::date and s.slot_date<(date_trunc('month',p_month)+interval '1 month')::date
  group by pp.user_id,pp.display_name,pp.position,pp.area order by 8 desc,5 desc,7 desc limit 100;
$$;

create or replace function public.get_player_performance(p_user_id uuid)
returns table(booking_id bigint,match_date date,stadium_name text,overall numeric,performance numeric,teamwork numeric,sportsmanship numeric)
language sql security definer set search_path = '' stable as $$
  select r.booking_id,s.slot_date,st.name,round(avg((r.performance+r.teamwork+r.sportsmanship)/3.0),1),round(avg(r.performance),1),round(avg(r.teamwork),1),round(avg(r.sportsmanship),1)
  from public.player_ratings r join public.stadium_bookings b on b.id=r.booking_id and b.status='confirmed'
  join public.stadium_time_slots s on s.id=b.slot_id join public.partner_stadiums st on st.id=s.stadium_id
  where r.rated_user_id=p_user_id group by r.booking_id,s.slot_date,st.name order by s.slot_date desc limit 10;
$$;

create or replace function public.get_my_match_codes()
returns table(booking_id bigint,stadium_name text,slot_date date,start_time time,join_code text,status text)
language sql security definer set search_path = '' stable as $$
 select b.id,st.name,s.slot_date,s.start_time,b.join_code,b.status from public.stadium_bookings b
 join public.stadium_time_slots s on s.id=b.slot_id join public.partner_stadiums st on st.id=s.stadium_id
 where b.customer_id=auth.uid() order by s.slot_date desc,s.start_time desc limit 30;
$$;

revoke all on function public.join_match_by_code(text,text),public.submit_player_rating(bigint,uuid,smallint,smallint,smallint,text),public.get_my_rateable_players(),public.get_my_match_codes() from public,anon;
grant execute on function public.join_match_by_code(text,text),public.submit_player_rating(bigint,uuid,smallint,smallint,smallint,text),public.get_my_rateable_players(),public.get_my_match_codes() to authenticated;
revoke all on function public.get_monthly_leaderboard(date),public.get_player_performance(uuid) from public;
grant execute on function public.get_monthly_leaderboard(date),public.get_player_performance(uuid) to anon,authenticated;
