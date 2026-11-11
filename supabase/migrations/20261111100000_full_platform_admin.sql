-- Expand owner-only administration to the operational data used by the NextMove app.
-- Secret-bearing tables are deliberately excluded: push endpoints/keys and match join codes.
-- This migration grants the authenticated owner read, insert and update access through RLS.
-- It does not grant delete access. app_admin_audit stays read-only.

do $$
declare t text;
begin
  foreach t in array array[
    'advertisements','app_campaigns','app_admin_audit','app_notifications','app_push_deliveries',
    'football_clip_ratings','football_clips','market_products','match_join_attempts','match_participants',
    'meal_orders','nutrition_plan_orders','partner_commission_rules','partner_contracts','partner_financial_entries',
    'partner_notifications','partner_profiles','partner_documents','partner_settlements','partner_stadiums',
    'platform_stats','player_profiles','player_ratings','product_orders','restaurant_meals','sports_catalog',
    'stadium_booking_shares','stadium_bookings','stadium_time_slots','training_booking_requests',
    'training_coaches','training_programs','training_subscriptions'
  ] loop
    if to_regclass('public.' || t) is not null then
      execute format('alter table public.%I enable row level security', t);
      if t = 'app_admin_audit' then
        execute format('grant select on table public.%I to authenticated', t);
        execute format('drop policy if exists %I on public.%I', 'platform owner reads ' || t, t);
        execute format('create policy %I on public.%I for select to authenticated using ((select public.is_platform_admin()))', 'platform owner reads ' || t, t);
      else
        execute format('grant select, insert, update on table public.%I to authenticated', t);
        execute format('drop policy if exists %I on public.%I', 'platform owner manages ' || t, t);
        execute format('create policy %I on public.%I for all to authenticated using ((select public.is_platform_admin())) with check ((select public.is_platform_admin()))', 'platform owner manages ' || t, t);
      end if;
    end if;
  end loop;
end;
$$;
