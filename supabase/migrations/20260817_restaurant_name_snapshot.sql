alter table public.restaurant_meals
  add column if not exists restaurant_name text not null default 'مطعم معتمد';

create or replace function public.set_restaurant_meal_owner_name()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  profile_name text;
begin
  select business_name into profile_name
  from public.partner_profiles
  where user_id = new.owner_id
    and partner_role = 'restaurant'
    and status = 'approved';

  if profile_name is null then
    raise exception 'RESTAURANT_NOT_APPROVED';
  end if;

  new.restaurant_name := profile_name;
  return new;
end;
$function$;

drop trigger if exists set_restaurant_meal_owner_name_trigger on public.restaurant_meals;
create trigger set_restaurant_meal_owner_name_trigger
before insert or update of owner_id on public.restaurant_meals
for each row execute function public.set_restaurant_meal_owner_name();

revoke all on function public.set_restaurant_meal_owner_name() from public, anon, authenticated;

