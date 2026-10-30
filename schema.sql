-- DriveEase – Supabase (PostgreSQL) schema
-- Run once in: Supabase dashboard → SQL Editor → New query → Run

create extension if not exists btree_gist;

-- ---------- Tables ----------
create table public.profiles (
  id    uuid primary key references auth.users(id) on delete cascade,
  name  text not null,
  email text not null unique,
  role  text not null default 'user' check (role in ('user','admin'))
);

create table public.cars (
  id         bigint primary key,
  name       text not null,
  type       text not null,
  seats      int  not null check (seats > 0),
  fuel       text not null,
  price      int  not null check (price >= 100),
  year       int  not null,
  rating     numeric(2,1) not null default 4.3,
  trans      text not null default 'Manual',
  mileage    text not null default '—',
  is_new     boolean not null default false,
  photo      text,
  maint_from date,
  maint_to   date
);

create table public.bookings (
  id          text primary key,
  car_id      bigint references public.cars(id) on delete set null,
  car_name    text not null,
  car_type    text,
  car_year    int,
  car_photo   text,
  user_id     uuid not null references auth.users(id) on delete cascade,
  user_email  text not null,
  user_name   text not null,
  start_date  date not null,
  end_date    date not null,
  days        int  not null,
  addons      jsonb not null default '[]',
  coupon      text default '',
  base        numeric(12,2) not null default 0,
  weekly      numeric(12,2) not null default 0,
  coupon_amt  numeric(12,2) not null default 0,
  addon_amt   numeric(12,2) not null default 0,
  gst         numeric(12,2) not null default 0,
  total       numeric(12,2) not null check (total >= 0),
  payment     text,
  txn         text,
  status      text not null default 'confirmed' check (status in ('confirmed','cancelled')),
  paid_on     text,
  delivery_fee     numeric(12,2) not null default 0,
  delivery_address text not null default '',
  created_at  timestamptz not null default now(),
  check (end_date >= start_date),
  -- the database itself refuses double-booking of a car
  constraint no_double_booking exclude using gist (
    car_id with =,
    daterange(start_date, end_date, '[]') with &&
  ) where (status = 'confirmed')
);

create index bookings_user_idx on public.bookings(user_id);
create index bookings_car_idx  on public.bookings(car_id);

-- ---------- Helpers ----------
create or replace function public.is_admin() returns boolean
language sql security definer set search_path = public stable as $$
  select exists (select 1 from public.profiles where id = auth.uid() and role = 'admin');
$$;

-- Lets any logged-in user see which dates are taken, without seeing anyone's details
create or replace function public.booked_slots()
returns table (id text, car_id bigint, start_date date, end_date date)
language sql security definer set search_path = public stable as $$
  select id, car_id, start_date, end_date from public.bookings where status = 'confirmed';
$$;
revoke execute on function public.booked_slots() from public, anon;
grant  execute on function public.booked_slots() to authenticated;

-- Auto-create a profile whenever someone signs up
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, name, email, role)
  values (new.id, coalesce(new.raw_user_meta_data->>'name', split_part(new.email,'@',1)), lower(new.email), 'user');
  return new;
end $$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------- Row Level Security ----------
alter table public.profiles enable row level security;
alter table public.cars     enable row level security;
alter table public.bookings enable row level security;

create policy "profiles: read own or admin" on public.profiles
  for select to authenticated using (id = auth.uid() or public.is_admin());

create policy "cars: anyone logged in can read" on public.cars
  for select to authenticated using (true);
create policy "cars: admin manages" on public.cars
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

create policy "bookings: read own or admin" on public.bookings
  for select to authenticated using (user_id = auth.uid() or public.is_admin());
create policy "bookings: create own" on public.bookings
  for insert to authenticated with check (user_id = auth.uid());
create policy "bookings: update own or admin" on public.bookings
  for update to authenticated
  using (user_id = auth.uid() or public.is_admin())
  with check (user_id = auth.uid() or public.is_admin());
create policy "bookings: admin deletes" on public.bookings
  for delete to authenticated using (public.is_admin());

-- ---------- Seed: fleet ----------
insert into public.cars (id, name, type, seats, fuel, price, year, rating, trans, mileage, is_new) values
  (1, 'Tata Curvv', 'SUV', 5, 'Petrol', 3500, 2024, 4.6, 'Automatic', '17 kmpl', true),
  (2, 'Mahindra Thar Roxx', 'SUV', 5, 'Diesel', 4200, 2024, 4.7, 'Automatic', '15 kmpl', true),
  (3, 'Tata Nexon 2024', 'SUV', 5, 'Petrol', 3200, 2024, 4.6, 'Automatic', '17 kmpl', true),
  (4, 'Hyundai Creta 2024', 'SUV', 5, 'Petrol', 3300, 2024, 4.7, 'Automatic', '17 kmpl', true),
  (5, 'Maruti Swift 2024', 'Hatchback', 5, 'Petrol', 1800, 2024, 4.5, 'Manual', '24 kmpl', true),
  (6, 'Maruti Fronx', 'SUV', 5, 'Petrol', 2400, 2024, 4.5, 'Automatic', '20 kmpl', true),
  (7, 'Mahindra XUV 3XO', 'SUV', 5, 'Petrol', 2900, 2024, 4.6, 'Automatic', '18 kmpl', true),
  (8, 'Hyundai Exter', 'SUV', 5, 'Petrol', 2200, 2024, 4.4, 'Manual', '19 kmpl', true),
  (9, 'Tata Punch', 'SUV', 5, 'Petrol', 2100, 2023, 4.4, 'Automatic', '18 kmpl', false),
  (10, 'Honda Elevate', 'SUV', 5, 'Petrol', 3100, 2023, 4.5, 'Automatic', '16 kmpl', false),
  (11, 'Hyundai Creta 2022', 'SUV', 5, 'Diesel', 2800, 2022, 4.5, 'Automatic', '18 kmpl', false),
  (12, 'Kia Seltos', 'SUV', 5, 'Petrol', 2900, 2022, 4.4, 'Automatic', '16 kmpl', false),
  (13, 'Kia Sonet', 'SUV', 5, 'Petrol', 2400, 2022, 4.3, 'Automatic', '18 kmpl', false),
  (14, 'Honda City', 'Sedan', 5, 'Petrol', 2500, 2021, 4.5, 'Automatic', '18 kmpl', false),
  (15, 'Hyundai Verna', 'Sedan', 5, 'Petrol', 2600, 2021, 4.4, 'Automatic', '20 kmpl', false),
  (16, 'Skoda Slavia', 'Sedan', 5, 'Petrol', 2700, 2022, 4.3, 'Automatic', '19 kmpl', false),
  (17, 'Tata Altroz', 'Hatchback', 5, 'Diesel', 1900, 2021, 4.2, 'Manual', '23 kmpl', false),
  (18, 'Maruti Baleno', 'Hatchback', 5, 'Petrol', 1800, 2021, 4.3, 'Automatic', '19 kmpl', false),
  (19, 'Tata Harrier', 'SUV', 5, 'Diesel', 3600, 2021, 4.6, 'Manual', '16 kmpl', false),
  (20, 'Mahindra XUV700', 'SUV', 7, 'Diesel', 4500, 2021, 4.7, 'Automatic', '16 kmpl', false),
  (21, 'Mahindra Thar', 'SUV', 4, 'Diesel', 4000, 2020, 4.8, 'Manual', '15 kmpl', false),
  (22, 'Toyota Innova Crysta', 'MUV', 7, 'Diesel', 3800, 2020, 4.7, 'Manual', '14 kmpl', false),
  (23, 'Maruti Ertiga', 'MUV', 7, 'CNG', 2400, 2021, 4.3, 'Manual', '26 km/kg', false),
  (24, 'Tata Nexon EV', 'SUV', 5, 'Electric', 3200, 2022, 4.5, 'Automatic', '325 km range', false),
  (25, 'Toyota Fortuner', 'SUV', 7, 'Diesel', 5500, 2021, 4.9, 'Automatic', '12 kmpl', false)
on conflict (id) do nothing;

-- ---------- After creating the two demo accounts through the site's Sign up page ----------
-- (admin@driveease.com / admin123 and user@driveease.com / user123), make the admin:
-- update public.profiles set role = 'admin' where email = 'admin@driveease.com';
