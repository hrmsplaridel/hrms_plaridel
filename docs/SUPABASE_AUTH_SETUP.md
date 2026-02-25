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

### Fix: "Could not find the 'vacancies' column" (PGRST204)

**If you get:** `PostgrestException ... Could not find the 'vacancies' column of 'job_vacancy_announcement'` when you tap **Save and display on landing page**, your table was created before the multiple-vacancies feature. Add the column in Supabase:

1. Open **Supabase Dashboard → SQL Editor → New query**.
2. Paste and run:

```sql
alter table public.job_vacancy_announcement
  add column if not exists vacancies jsonb default '[]'::jsonb;
```

3. Try saving again from the admin form.

---

### Query 5: Create `job_vacancy_announcement` table

**If you get:** `Could not find the table 'public.job_vacancy_announcement'` (PGRST205) when saving the form, run the SQL below in Supabase: **Dashboard → SQL Editor → New query** → paste → **Run**.

Run this in **SQL Editor** after Part 2–3.

```sql
-- Single-row table: job vacancy announcement for the landing page (RSP module).
create table if not exists public.job_vacancy_announcement (
  id text primary key default 'default',
  has_vacancies boolean not null default true,
  headline text,
  body text,
  vacancies jsonb default '[]'::jsonb,
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

-- Allow authenticated to insert (so first save can create the default row if missing)
create policy "Authenticated can insert job vacancy announcement"
  on public.job_vacancy_announcement for insert
  with check (auth.role() = 'authenticated');

comment on table public.job_vacancy_announcement is 'Single row: controls Job Vacancies section on landing page. RSP form in admin dashboard.';
```

**If the table already exists** (you ran Query 5 before), add the multiple-vacancies column:

```sql
alter table public.job_vacancy_announcement
  add column if not exists vacancies jsonb default '[]'::jsonb;
```

After this, the RSP form in the admin dashboard can save the announcement (and multiple job vacancy entries), and the landing page will display it.

---

## Part 6: Recruitment applications and exam results (RSP monitoring)

Applicants submit basic info and take a screening exam. Admins view all applications and exam results in the RSP module.

### Query 6: Create `recruitment_applications` and `recruitment_exam_results` tables

Run this in **SQL Editor** after Part 5.

```sql
-- Applications: basic info submitted in Step 1 (documents).
create table if not exists public.recruitment_applications (
  id uuid primary key default gen_random_uuid(),
  full_name text not null,
  email text not null,
  phone text,
  resume_notes text,
  status text not null default 'submitted' check (status in ('submitted', 'document_approved', 'document_declined', 'exam_taken', 'passed', 'failed', 'registered')),
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- Exam results: one row per application after they take the exam.
create table if not exists public.recruitment_exam_results (
  id uuid primary key default gen_random_uuid(),
  application_id uuid not null references public.recruitment_applications (id) on delete cascade,
  score_percent numeric not null,
  passed boolean not null,
  answers_json jsonb,
  submitted_at timestamptz default now(),
  unique(application_id)
);

alter table public.recruitment_applications enable row level security;
alter table public.recruitment_exam_results enable row level security;

-- Anyone can insert (applicants without login)
create policy "Anyone can insert recruitment applications"
  on public.recruitment_applications for insert with check (true);

-- Applicants can read own (by email in session we could add later); for now allow public read for simplicity or restrict. Admin needs read.
create policy "Public can read recruitment applications"
  on public.recruitment_applications for select using (true);

-- Only authenticated can update (e.g. admin marking status)
create policy "Authenticated can update recruitment applications"
  on public.recruitment_applications for update using (auth.role() = 'authenticated');

-- Anyone can insert exam result (applicant submits exam)
create policy "Anyone can insert exam results"
  on public.recruitment_exam_results for insert with check (true);

-- Public read so admin (authenticated) can read
create policy "Public can read exam results"
  on public.recruitment_exam_results for select using (true);

create index idx_recruitment_applications_created on public.recruitment_applications (created_at desc);
create index idx_recruitment_exam_results_application on public.recruitment_exam_results (application_id);
```

---

### Query 6b: Add attachment columns and Storage bucket (for applicant file upload)

Applicants can attach a file (e.g. resume); admins can view, download, and **approve or decline** it from RSP. Only **document_approved** applications can proceed to the exam.

**If you already ran Query 6 with the old status check**, run this to allow the new statuses (document_approved, document_declined):

```sql
alter table public.recruitment_applications drop constraint if exists recruitment_applications_status_check;
alter table public.recruitment_applications add constraint recruitment_applications_status_check
  check (status in ('submitted', 'document_approved', 'document_declined', 'exam_taken', 'passed', 'failed', 'registered'));
```

**1. Add columns to `recruitment_applications`** (run in SQL Editor):

```sql
alter table public.recruitment_applications
  add column if not exists attachment_path text,
  add column if not exists attachment_name text;
```

**2. Allow applicants (anon) to save attachment path after upload**

Applicants are not logged in when they submit. The app uploads the file to Storage, then updates the application row with `attachment_path` and `attachment_name`. The default update policy only allows `authenticated` users, so that update was failing and the admin never saw the attachment. Run this so **anon** can update the row only when the row stays in `submitted` status (so they can only set attachment path/name, not change status):

```sql
create policy "Anon can set attachment on submitted application"
  on public.recruitment_applications for update
  to anon
  using (true)
  with check (status = 'submitted');
```

**3. Create Storage bucket and policies**

- In **Dashboard → Storage**, click **New bucket**. Name: `recruitment-attachments`. Leave it **private** (so only authenticated users can download).
- Go to **Storage → Policies** (or **recruitment-attachments → Policies**). Add:

  - **Policy 1 (upload):** Name `Allow public upload`, Operation **INSERT**, Target **All roles** (or **anon**), WITH CHECK expression: `bucket_id = 'recruitment-attachments'`.
  - **Policy 2 (download/list):** Name `Allow authenticated read`, Operation **SELECT**, Target **authenticated**, USING expression: `bucket_id = 'recruitment-attachments'`. This lets admins download files and list objects (needed for **Sync attachments from storage** in the admin panel).

So applicants (no login) can upload; only logged-in admins can read, download, and list.

**If attachments still show as "No file" in admin:**

1. **For new applications:** Run the SQL in step 2 above so that applicants (anon) can update the application row with `attachment_path` and `attachment_name` after uploading.
2. **For applications that already submitted (file in storage but DB not updated):** In the admin **Applications & Exam Results** view, click **Sync attachments from storage**. This links existing files in the bucket to applications that are missing attachment path. Then refresh to see the download option.

**"Sync attachments from storage" shows "No files found" or "listing not allowed":**

- **Admin must be logged in with Supabase Auth.** The app uses `Supabase.instance.client.auth.currentSession`; if there is no session (e.g. you opened the admin UI without going through the normal Login with Supabase), storage list will fail or return empty. Use the app’s **Login** (Supabase Email/Password) so the client has an authenticated session. Do not rely on a custom users table only; the Storage bucket is private and list/download require the authenticated role.
- **Storage policy:** Ensure Policy 2 (SELECT for `authenticated`) exists on the bucket `recruitment-attachments`. In **Dashboard → Storage → recruitment-attachments → Policies**, you should have a policy with Operation **SELECT** and Target **authenticated**, USING `bucket_id = 'recruitment-attachments'`. This allows listing and downloading; without it, listing returns empty or permission denied.
- **Download:** The admin UI uses signed URLs (`createSignedUrl`) to download; that also requires an authenticated session and the same SELECT policy.

---

### Query 6c: Exam questions (admin-editable BEI and other exam questions)

Run this so admins can view and edit exam questions (e.g. the 8 BEI questions). Applicants see the questions from this table.

```sql
create table if not exists public.recruitment_exam_questions (
  id uuid primary key default gen_random_uuid(),
  exam_type text not null default 'bei',
  sort_order int not null default 0,
  question_text text not null,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

alter table public.recruitment_exam_questions enable row level security;

-- Anyone can read (applicants need to load questions)
create policy "Public can read exam questions"
  on public.recruitment_exam_questions for select using (true);

-- Only authenticated (admin) can insert/update/delete
create policy "Authenticated can insert exam questions"
  on public.recruitment_exam_questions for insert with check (auth.role() = 'authenticated');
create policy "Authenticated can update exam questions"
  on public.recruitment_exam_questions for update using (auth.role() = 'authenticated');
create policy "Authenticated can delete exam questions"
  on public.recruitment_exam_questions for delete using (auth.role() = 'authenticated');

create index idx_recruitment_exam_questions_type_order on public.recruitment_exam_questions (exam_type, sort_order);
```

**For General Exam (multiple choice), add columns** (run after creating the table):

```sql
alter table public.recruitment_exam_questions
  add column if not exists options_json jsonb,
  add column if not exists correct_index int;
```

Optional: seed the default 8 BEI questions (run once so admin can edit them in the app):

```sql
insert into public.recruitment_exam_questions (exam_type, sort_order, question_text) values
  ('bei', 1, 'Tell me about a time when you had to collaborate with a co-worker that you had a hard time getting along with?'),
  ('bei', 2, 'Describe for me a time when you were under a significant amount of pressure at work. How did you deal with it?'),
  ('bei', 3, 'Tell me about a time when you were ask to work on a task that you had never done before.'),
  ('bei', 4, 'Tell me about a time when you had to cultivate a relationship with a new client. What did you do?'),
  ('bei', 5, 'Describe a time when you disagreed with your boss. What did you do?'),
  ('bei', 6, 'Describe your greatest challenge.'),
  ('bei', 7, 'What was your greatest accomplishment?'),
  ('bei', 8, 'Tell me about a time you failed.');
```

Optional: seed the default 5 General Exam questions (run once so admin can edit them):

```sql
insert into public.recruitment_exam_questions (exam_type, sort_order, question_text, options_json, correct_index) values
  ('general', 1, '_____ : play ; sing : anthem', '["Play", "Scene", "Theatre", "Field"]'::jsonb, 2),
  ('general', 2, 'Choose the right order. (1) Her father understood that she boiled the egg for the first time. (2) He took up a newspaper and read for ten minutes. (3) Father asked Kate to boil an egg soft for his breakfast. (4) Kate answered that it wasn''t ready because it was still very hard. (5) Then he asked Kate if the egg was ready.', '["3, 2, 5, 4, 1", "4, 2, 3, 1, 5", "2, 4, 3, 1, 5", "5, 3, 1, 2, 4", "1, 3, 4, 5, 2"]'::jsonb, 0),
  ('general', 3, 'Clock : Time : : Thermometer : _____', '["Heat", "Radiation", "Energy", "Temperature"]'::jsonb, 3),
  ('general', 4, '(Idiomatic Expression) "Even though they had a nasty fight, they decided to bury the hatchet and move on." What does "bury the hatchet" mean?', '["Kill the enemy", "Remember the past", "Bury the dead", "Forget the past quarrel"]'::jsonb, 3),
  ('general', 5, 'What should come in the place of (?) in the following letter series? BE GJ LO QT ?', '["VZ", "WZ", "VY", "UY"]'::jsonb, 2);
```

Optional: seed the default 9 Mathematics exam questions (run once so admin can edit them):

```sql
insert into public.recruitment_exam_questions (exam_type, sort_order, question_text, options_json, correct_index) values
  ('math', 1, 'Linus needs ribbon for three bookmarks. One bookmark is 12½ inches long and the other two are 7¼ inches long each. What total length of ribbon does he need?', '["26 inches", "19 inches", "19¾ inches", "27 inches"]'::jsonb, 3),
  ('math', 2, 'What is the next number in the sequence? 320, 160, 80, 40, ____', '["35", "30", "10", "20"]'::jsonb, 3),
  ('math', 3, 'Multiply the second-highest odd number and the second-lowest in the list: 2, 3, 4, 7, 1, 68.', '["3", "6", "7", "21"]'::jsonb, 1),
  ('math', 4, 'Amy worked 4/5 of the days last year. How many days did she work in a year?', '["273", "300", "292", "281"]'::jsonb, 2),
  ('math', 5, 'What is the next number in the sequence? 13, 21, 34, 55, 89, ____?', '["95", "104", "123", "144"]'::jsonb, 3),
  ('math', 6, 'If 0.75 : x :: 5 : 8, then x is equal to', '["1.12", "1.2", "1.28", "1.30"]'::jsonb, 1),
  ('math', 7, 'Lindsay purchased a pocketbook for P 45 and a pair of shoes for P 55. The sales tax on the items was 6%. How much sales tax did she pay?', '["P 2.70", "P 3.30", "P 6.00", "P 6.60"]'::jsonb, 2),
  ('math', 8, 'A baseball pitcher won 80% of the games he pitched. If he pitched 35 ballgames, how many games did he win?', '["70", "28", "43", "35"]'::jsonb, 1),
  ('math', 9, 'A large pipe dispenses 750 gallons of water in 50 seconds. At this rate, how long will it take to dispense 330 gallons?', '["14 seconds", "33 seconds", "22 seconds", "27 seconds"]'::jsonb, 2);
```

Optional: seed the default 5 General Information exam questions (run once so admin can edit them):

```sql
insert into public.recruitment_exam_questions (exam_type, sort_order, question_text, options_json, correct_index) values
  ('general_info', 1, 'The right to just and favourable working conditions guarantees every Filipino Worker a right to ________.', '["None of these", "Limited opportunities", "Stricter rules on break time", "Fair remuneration for equal work"]'::jsonb, 3),
  ('general_info', 2, 'In order for the state to promote social justice to ensure the dignity, welfare and security of all people, it has to ________.', '["Equability diffuse property ownership and right", "Regulate the disposition of private property", "Regulate the acquisition of private property", "All of the above"]'::jsonb, 3),
  ('general_info', 3, 'It states that ''no person shall be deprived of life, liberty, or property without due process of law, nor any person be denied the equal protection of the laws.''', '["Article VI", "Bill of Rights", "Republic Act", "Court Order"]'::jsonb, 1),
  ('general_info', 4, 'The 1987 Constitution contains at least 3 sets of provisions, which one of the following provision is not included?', '["Constitution of Government", "Constitution of Universality", "Constitution of Sovereignty", "Constitution of Liberty"]'::jsonb, 1),
  ('general_info', 5, 'All of the following is true except.', '["No person shall be compelled to be a witness against himself", "No person shall be imprisoned for non-payment of debt or poll tax", "No ex post facto law or bill of attainder shall not be enacted.", "No person shall be detained solely by reason of his political beliefs and aspirations."]'::jsonb, 2);
```

---

## Part 7: Background Investigation (BI) and Performance Evaluation forms (RSP)

The RSP module includes two admin forms: **Background Investigation (BI) Form** and **Performance / Functional Evaluation Form**. Run the following in **SQL Editor** to create the tables.

### Query 7a: Background Investigation (BI) form entries

One row per respondent evaluation (an applicant can have multiple respondents). Competency ratings are 1–5 (1 = Much development needed, 5 = Shows strength).

```sql
create table if not exists public.bi_form_entries (
  id uuid primary key default gen_random_uuid(),
  applicant_name text not null,
  applicant_department text,
  applicant_position text,
  position_applied_for text,
  respondent_name text not null,
  respondent_position text,
  respondent_relationship text not null check (respondent_relationship in ('supervisor', 'peer', 'subordinate')),
  rating_1 smallint check (rating_1 >= 1 and rating_1 <= 5),
  rating_2 smallint check (rating_2 >= 1 and rating_2 <= 5),
  rating_3 smallint check (rating_3 >= 1 and rating_3 <= 5),
  rating_4 smallint check (rating_4 >= 1 and rating_4 <= 5),
  rating_5 smallint check (rating_5 >= 1 and rating_5 <= 5),
  rating_6 smallint check (rating_6 >= 1 and rating_6 <= 5),
  rating_7 smallint check (rating_7 >= 1 and rating_7 <= 5),
  rating_8 smallint check (rating_8 >= 1 and rating_8 <= 5),
  rating_9 smallint check (rating_9 >= 1 and rating_9 <= 5),
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

alter table public.bi_form_entries enable row level security;

create policy "Authenticated can manage bi_form_entries"
  on public.bi_form_entries for all
  using (auth.role() = 'authenticated')
  with check (auth.role() = 'authenticated');

create index idx_bi_form_entries_created on public.bi_form_entries (created_at desc);
comment on table public.bi_form_entries is 'RSP: Background Investigation form submissions (one row per respondent evaluation).';
```

### Query 7b: Performance / Functional Evaluation form entries

Stores functional areas (checkboxes) and the three narrative answers.

```sql
create table if not exists public.performance_evaluation_entries (
  id uuid primary key default gen_random_uuid(),
  applicant_name text,
  functional_areas jsonb default '[]'::jsonb,
  other_functional_area text,
  performance_3_years text,
  challenges_coping text,
  compliance_attendance text,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

alter table public.performance_evaluation_entries enable row level security;

create policy "Authenticated can manage performance_evaluation_entries"
  on public.performance_evaluation_entries for all
  using (auth.role() = 'authenticated')
  with check (auth.role() = 'authenticated');

create index idx_performance_evaluation_entries_created on public.performance_evaluation_entries (created_at desc);
comment on table public.performance_evaluation_entries is 'RSP: Performance/Functional evaluation form (functional areas + 3 narrative questions).';
```

### Query 7c: Individual Development Plan (IDP) entries

Stores employee IDP data: personal/position info, qualifications, succession analysis (target positions, performance/competence ratings, priority), and development plan rows (objectives, L&D program, requirements, time frame).

```sql
create table if not exists public.idp_entries (
  id uuid primary key default gen_random_uuid(),
  name text,
  position text,
  category text,
  division text,
  department text,
  education text,
  experience text,
  training text,
  eligibility text,
  target_position_1 text,
  target_position_2 text,
  avg_rating text,
  opcr text,
  ipcr text,
  performance_rating text check (performance_rating is null or performance_rating in ('poor', 'unsatisfactory', 'very_satisfactory', 'outstanding')),
  competency_description text,
  competence_rating text check (competence_rating is null or competence_rating in ('basic', 'intermediate', 'advanced', 'superior')),
  succession_priority_score text,
  succession_priority_rating text check (succession_priority_rating is null or succession_priority_rating in ('priority', 'priority_2', 'priority_3')),
  development_plan_rows jsonb default '[]'::jsonb,
  prepared_by text,
  reviewed_by text,
  noted_by text,
  approved_by text,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

alter table public.idp_entries enable row level security;

create policy "Authenticated can manage idp_entries"
  on public.idp_entries for all
  using (auth.role() = 'authenticated')
  with check (auth.role() = 'authenticated');

create index idx_idp_entries_created on public.idp_entries (created_at desc);
comment on table public.idp_entries is 'RSP: Individual Development Plan (IDP) form entries.';
```

### Query 7d: Applicants Profile entries

Stores applicants profile worksheets: job vacancy details (position, minimum requirements, posting/closing dates) and a list of applicants (name, course, address, sex, age, civil status, remark/disability). One row per profile; applicants are stored as a jsonb array.

```sql
create table if not exists public.applicants_profile_entries (
  id uuid primary key default gen_random_uuid(),
  position_applied_for text,
  minimum_requirements text,
  date_of_posting text,
  closing_date text,
  applicants jsonb default '[]'::jsonb,
  prepared_by text,
  checked_by text,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

alter table public.applicants_profile_entries enable row level security;

create policy "Authenticated can manage applicants_profile_entries"
  on public.applicants_profile_entries for all
  using (auth.role() = 'authenticated')
  with check (auth.role() = 'authenticated');

create index idx_applicants_profile_entries_created on public.applicants_profile_entries (created_at desc);
comment on table public.applicants_profile_entries is 'RSP: Applicants Profile form (job vacancy details + list of applicants per profile).';
```

Each element in the `applicants` jsonb array has: `name`, `course`, `address`, `sex`, `age`, `civil_status`, `remark_disability` (all optional text).

### Query 7e: Comparative Assessment of Candidates for Promotion

Stores the Merit Promotion and Selection Board comparative assessment form: position to be filled, minimum requirements (education, experience, eligibility, training), and a list of candidates with columns: present position/salary, education, training hours, related experience, eligibility, performance rating, remarks. Form only—no pre-filled names or values.

```sql
create table if not exists public.comparative_assessment_entries (
  id uuid primary key default gen_random_uuid(),
  position_to_be_filled text,
  min_req_education text,
  min_req_experience text,
  min_req_eligibility text,
  min_req_training text,
  candidates jsonb default '[]'::jsonb,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

alter table public.comparative_assessment_entries enable row level security;

create policy "Authenticated can manage comparative_assessment_entries"
  on public.comparative_assessment_entries for all
  using (auth.role() = 'authenticated')
  with check (auth.role() = 'authenticated');

create index idx_comparative_assessment_entries_created on public.comparative_assessment_entries (created_at desc);
comment on table public.comparative_assessment_entries is 'RSP: Comparative Assessment of Candidates for Promotion (form structure only).';
```

Each element in `candidates` has: `candidate_name`, `present_position_salary`, `education`, `training_hrs`, `related_experience`, `eligibility`, `performance_rating`, `remarks` (all optional text).

### Query 7f: Promotion Certification / Screening form

Stores the certification form: table of candidates with five data columns per candidate, certification date (day, month, year), and signatory. Form only—no pre-filled names or values.

```sql
create table if not exists public.promotion_certification_entries (
  id uuid primary key default gen_random_uuid(),
  position_for_promotion text,
  candidates jsonb default '[]'::jsonb,
  date_day text,
  date_month text,
  date_year text,
  signatory_name text,
  signatory_title text,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

alter table public.promotion_certification_entries enable row level security;

create policy "Authenticated can manage promotion_certification_entries"
  on public.promotion_certification_entries for all
  using (auth.role() = 'authenticated')
  with check (auth.role() = 'authenticated');

create index idx_promotion_certification_entries_created on public.promotion_certification_entries (created_at desc);
comment on table public.promotion_certification_entries is 'RSP: Certification that candidate(s) have been screened and found qualified for promotion (form structure only).';
```

Each element in `candidates` has: `name`, `col1`, `col2`, `col3`, `col4`, `col5` (all optional text).

### Query 7g: Selection Line-up entries

Stores the Selection Line-up form: date, name of agency/office, vacant position, item no., and a table of applicants (name, education, experience, training, eligibility). Prepared-by signatory. Form only—no pre-filled names or values.

```sql
create table if not exists public.selection_lineup_entries (
  id uuid primary key default gen_random_uuid(),
  date text,
  name_of_agency_office text,
  vacant_position text,
  item_no text,
  applicants jsonb default '[]'::jsonb,
  prepared_by_name text,
  prepared_by_title text,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

alter table public.selection_lineup_entries enable row level security;

create policy "Authenticated can manage selection_lineup_entries"
  on public.selection_lineup_entries for all
  using (auth.role() = 'authenticated')
  with check (auth.role() = 'authenticated');

create index idx_selection_lineup_entries_created on public.selection_lineup_entries (created_at desc);
comment on table public.selection_lineup_entries is 'RSP: Selection Line-up form (applicants table: name, education, experience, training, eligibility). Form only.';
```

Each element in `applicants` has: `name`, `education`, `experience`, `training`, `eligibility` (all optional text).

### Query 7h: Turn-Around Time entries

Stores the Merit Promotion and Selection Board Turn-Around Time form: position, office, no. of vacant position, date of publication, end search, Q.S., and a table of applicants with columns (name, date initial assessment, date contract exam, skills trade/exam result, date deliberation, date job offer, acceptance date, date assumption to duty, no. of days to fill-up, overall cost per hire). Prepared by / Noted by signatories. Form only—no pre-filled names or values.

```sql
create table if not exists public.turn_around_time_entries (
  id uuid primary key default gen_random_uuid(),
  position text,
  office text,
  no_of_vacant_position text,
  date_of_publication text,
  end_search text,
  qs text,
  applicants jsonb default '[]'::jsonb,
  prepared_by_name text,
  prepared_by_title text,
  noted_by_name text,
  noted_by_title text,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

alter table public.turn_around_time_entries enable row level security;

create policy "Authenticated can manage turn_around_time_entries"
  on public.turn_around_time_entries for all
  using (auth.role() = 'authenticated')
  with check (auth.role() = 'authenticated');

create index idx_turn_around_time_entries_created on public.turn_around_time_entries (created_at desc);
comment on table public.turn_around_time_entries is 'RSP: Turn-Around Time form (recruitment/hiring process tracking per applicant). Form only.';
```

Each element in `applicants` has: `name`, `date_initial_assessment`, `date_contract_exam`, `skills_trade_exam_result`, `date_deliberation`, `date_job_offer`, `acceptance_date`, `date_assumption_to_duty`, `no_of_days_to_fill_up`, `overall_cost_per_hire` (all optional text).

### Query 7i: Training Need Analysis entries (L&D)

Stores the L&D Training Need Analysis and Consolidated Report: FOR CY [year], DEPARTMENT, and a table of rows with columns: name_position, goal, behavior, skills_knowledge, need_for_training, training_recommendations. Form only—no pre-filled names or values.

```sql
create table if not exists public.training_need_analysis_entries (
  id uuid primary key default gen_random_uuid(),
  cy_year text,
  department text,
  rows jsonb default '[]'::jsonb,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

alter table public.training_need_analysis_entries enable row level security;

create policy "Authenticated can manage training_need_analysis_entries"
  on public.training_need_analysis_entries for all
  using (auth.role() = 'authenticated')
  with check (auth.role() = 'authenticated');

create index idx_training_need_analysis_entries_created on public.training_need_analysis_entries (created_at desc);
comment on table public.training_need_analysis_entries is 'L&D: Training Need Analysis and Consolidated Report (CY year, department, table rows). Form only.';
```

Each element in `rows` has: `name_position`, `goal`, `behavior`, `skills_knowledge`, `need_for_training`, `training_recommendations` (all optional text).

### Query 7j: Action Brainstorming and Coaching Worksheet entries (L&D)

Stores the L&D Action Brainstorming and Coaching Worksheet: DEPARTMENT, DATE, instruction, table rows (name, stop_doing, do_less_of, keep_doing, do_more_of, start_doing, goal), certified_by, certification_date. Form only—no pre-filled names or values.

```sql
create table if not exists public.action_brainstorming_coaching_entries (
  id uuid primary key default gen_random_uuid(),
  department text,
  date text,
  "rows" jsonb default '[]'::jsonb,
  certified_by text,
  certification_date text,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

alter table public.action_brainstorming_coaching_entries enable row level security;

create policy "Authenticated can manage action_brainstorming_coaching_entries"
  on public.action_brainstorming_coaching_entries for all
  using (auth.role() = 'authenticated')
  with check (auth.role() = 'authenticated');

create index idx_action_brainstorming_coaching_entries_created on public.action_brainstorming_coaching_entries (created_at desc);
comment on table public.action_brainstorming_coaching_entries is 'L&D: Action Brainstorming and Coaching Worksheet (department, date, table rows, certified by). Form only.';
```

Each element in `rows` has: `name`, `stop_doing`, `do_less_of`, `keep_doing`, `do_more_of`, `start_doing`, `goal` (all optional text).

After running Query 7a–7j, the RSP and L&D dashboard can list, create, and edit all RSP and L&D forms. All forms use empty inputs by default (no names or values pre-filled).
