# Supabase setup: Login & Sign-up forms

This doc has everything you need so the **Login** and **Sign up** forms in the app work with Supabase.

---

## Part 1: Dashboard – Enable Email auth

1. Open **https://supabase.com/dashboard** and select your project.
2. Go to **Authentication** → **Providers**.
3. Enable **Email**.
4. (Optional) **Confirm email**:  
   - **ON** = user must click the link in the email before they can log in.  
   - **OFF** = user can log in right after signing up.
5. Click **Save**.

Without this, both login and sign-up will fail.

---

## Why can't I log in after creating an account?

**Most common cause: Email confirmation is ON.**

If **Confirm email** is enabled in **Authentication → Providers → Email**, Supabase sends a confirmation email after sign-up. The user **must click the link in that email** before they can log in. Until then, login will fail (often with "Email not confirmed" or similar).

**You have two options:**

| Option | What to do |
|--------|------------|
| **A) Confirm your email** | Check the inbox (and spam) for the email from Supabase and click the confirmation link. Then try logging in again. |
| **B) Allow login without confirming** | In Dashboard → **Authentication** → **Providers** → **Email**, turn **OFF** "Confirm email" and Save. New sign-ups can then log in immediately without clicking a link. (Use only if you don’t need to verify email.) |

---

## Part 2: SQL – Run in Supabase SQL Editor

Run the following in order in **SQL Editor** (Supabase Dashboard → **SQL Editor** → **New query**). Copy each block, paste, and run.

---

### Query 1: Create `profiles` table

This table stores full name and role (admin/employee) for each user. The app’s sign-up form sends `full_name` and `role`; this table holds them.

```sql
-- Table: profiles (one row per user, linked to auth.users)
create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  email text,
  full_name text,
  role text not null default 'employee' check (role in ('admin', 'employee')),
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- Enable Row Level Security (RLS)
alter table public.profiles enable row level security;

-- Users can read their own profile
create policy "Users can read own profile"
  on public.profiles for select
  using (auth.uid() = id);

-- Users can update their own profile (e.g. full_name)
create policy "Users can update own profile"
  on public.profiles for update
  using (auth.uid() = id);

-- Allow insert when the row is for the current user (used by trigger below)
create policy "Users can insert own profile"
  on public.profiles for insert
  with check (auth.uid() = id);

comment on table public.profiles is 'User profiles; id = auth.users.id. role: admin | employee.';
```

---

### Query 2: Function – Create profile on sign up

When a new user signs up, this function inserts a row into `profiles` using data from the sign-up form (`full_name`, `role`).

```sql
-- Function: create a profile row when a new user signs up
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, email, full_name, role)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data->>'full_name', ''),
    coalesce(nullif(trim(new.raw_user_meta_data->>'role'), ''), 'employee')
  );
  return new;
end;
$$;
```

---

### Query 3: Trigger – Run function after sign up

This trigger runs the function above every time a new row is added to `auth.users` (i.e. when someone signs up).

```sql
-- Trigger: after a new user is created in auth.users
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();
```

---

### Query 4 (optional): Backfill existing users

If you already had users **before** you created the `profiles` table, run this once so they get a profile row. If you have no users yet, you can skip it.

```sql
-- Create profile for any auth user that doesn't have one
insert into public.profiles (id, email, full_name, role)
select
  id,
  email,
  coalesce(raw_user_meta_data->>'full_name', ''),
  coalesce(nullif(trim(raw_user_meta_data->>'role'), ''), 'employee')
from auth.users
on conflict (id) do nothing;
```

---

## Part 3: How the app uses Supabase

| Form    | What the app does | What Supabase needs |
|---------|-------------------|----------------------|
| **Login** | Calls `auth.signInWithPassword(email, password)` | Email provider enabled; user exists (created in Dashboard or via Sign up). |
| **Sign up** | Calls `auth.signUp(email, password, data: { full_name, role })` | Email provider enabled; trigger + `profiles` table so `full_name` and `role` are saved. |

- **Login** works as soon as Email auth is enabled and the user has an account.
- **Sign up** works with Email auth + Query 1 + Query 2 + Query 3. Then new users get a `profiles` row with the role they chose (Admin/Employee).

---

## Part 4: Checklist

| Step | Where | Action |
|------|--------|--------|
| 1 | Dashboard → Authentication → Providers | Enable **Email** |
| 2 | SQL Editor | Run **Query 1** (create `profiles` table) |
| 3 | SQL Editor | Run **Query 2** (create `handle_new_user` function) |
| 4 | SQL Editor | Run **Query 3** (create trigger on `auth.users`) |
| 5 | SQL Editor | Run **Query 4** only if you had users before `profiles` existed |
| 6 | App | Test **Sign up** (new user), then **Login** with that user |

After this, the login and sign-up forms will work with Supabase.

---

## Part 5: Job Vacancy Announcement (RSP – landing page)

The **RSP** module in the admin dashboard lets you control what the **landing page** shows in the Job Vacancies section (e.g. “We are currently accepting applications” vs “There are no job vacancies”). The app reads and writes a single row in Supabase.

### Query 5: Create `job_vacancy_announcement` table

Run this in **SQL Editor** after Part 2–3.

```sql
-- Single-row table: job vacancy announcement for the landing page (RSP module).
create table if not exists public.job_vacancy_announcement (
  id text primary key default 'default',
  has_vacancies boolean not null default true,
  headline text,
  body text,
  updated_at timestamptz default now()
);

-- Ensure one row exists
insert into public.job_vacancy_announcement (id, has_vacancies, headline, body)
values ('default', true, null, null)
on conflict (id) do nothing;

-- Enable RLS
alter table public.job_vacancy_announcement enable row level security;

-- Anyone can read (so the landing page can show it without login)
create policy "Public can read job vacancy announcement"
  on public.job_vacancy_announcement for select
  using (true);

-- Only authenticated users can update (admin saves from RSP form)
create policy "Authenticated can update job vacancy announcement"
  on public.job_vacancy_announcement for update
  using (auth.role() = 'authenticated');

comment on table public.job_vacancy_announcement is 'Single row: controls Job Vacancies section on landing page. RSP form in admin dashboard.';
```

After this, the RSP form in the admin dashboard can save the announcement, and the landing page will display it.
