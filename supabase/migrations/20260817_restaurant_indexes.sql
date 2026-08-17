create index if not exists restaurant_meals_owner_id_idx on public.restaurant_meals(owner_id);
create index if not exists restaurant_meals_active_category_idx on public.restaurant_meals(category, created_at desc) where is_active = true;
create index if not exists meal_orders_meal_id_idx on public.meal_orders(meal_id);
create index if not exists meal_orders_customer_id_idx on public.meal_orders(customer_id);
create index if not exists meal_orders_restaurant_id_idx on public.meal_orders(restaurant_id);

