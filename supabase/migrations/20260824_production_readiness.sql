-- Production pages only show providers tied to approved partner/coach accounts.
-- Historical sample rows are retained for auditability but are not exposed.

-- A coach may only update lifecycle fields on subscriptions that belong to them.
drop policy if exists "Coaches update their subscriptions" on public.training_subscriptions;
create policy "Coaches update their subscriptions"
  on public.training_subscriptions for update
  to authenticated
  using ((select auth.uid()) = coach_id)
  with check ((select auth.uid()) = coach_id);

revoke update on public.training_subscriptions from authenticated;
grant update (status, starts_at, ends_at, updated_at)
  on public.training_subscriptions to authenticated;

-- Explicit Data API grants for launch-critical authenticated flows.
grant select on public.training_coaches, public.training_programs to anon, authenticated;
grant select, insert on public.training_subscriptions to authenticated;
grant select, insert on public.training_messages to authenticated;
grant select on public.partner_stadiums, public.stadium_time_slots to anon, authenticated;
grant select on public.stadium_bookings, public.stadium_booking_shares to authenticated;
grant select on public.market_products, public.restaurant_meals to anon, authenticated;
grant select, insert on public.product_orders, public.meal_orders to authenticated;
grant select, insert on public.training_booking_requests, public.nutrition_plan_orders to authenticated;

select private.sync_platform_stats();
