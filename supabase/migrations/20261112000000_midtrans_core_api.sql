create table if not exists public.invoices (
  id text primary key,
  customer_id text not null references public.customers(customer_id) on delete restrict,
  period text not null,
  amount integer not null check (amount > 0),
  currency text not null default 'IDR' check (currency = 'IDR'),
  status text not null default 'unpaid'
    check (status in ('unpaid', 'paid', 'expired')),
  due_at timestamptz not null,
  paid_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

do $$
begin
  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'invoices'
      and column_name = 'invoice_id'
  ) and not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'invoices'
      and column_name = 'id'
  ) then
    alter table public.invoices rename column invoice_id to id;
  end if;
end;
$$;

alter table public.invoices
  add column if not exists currency text not null default 'IDR',
  add column if not exists paid_at timestamptz;

alter table public.invoices
  drop constraint if exists invoices_currency_check,
  drop constraint if exists invoices_status_check,
  add constraint invoices_currency_check check (currency = 'IDR'),
  add constraint invoices_status_check
    check (status in ('unpaid', 'paid', 'expired'));

create index if not exists invoices_customer_status_idx
  on public.invoices(customer_id, status);

alter table public.invoices enable row level security;
drop policy if exists "Linked customers can read their invoices"
  on public.invoices;
create policy "Linked customers can read their invoices"
  on public.invoices
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.profiles as profile
      where profile.id = (select auth.uid())
        and profile.customer_id = invoices.customer_id
    )
  );
revoke all on public.invoices from public, anon, authenticated;
grant select on public.invoices to authenticated;
grant all on public.invoices to service_role;

create table if not exists public.midtrans_payments (
  order_id text primary key,
  invoice_id text not null references public.invoices(id) on delete restrict,
  user_id uuid not null references auth.users(id) on delete restrict,
  amount integer not null check (amount > 0),
  status text not null
    check (status in ('creating', 'pending', 'paid', 'failed', 'expired', 'cancelled')),
  snap_token text,
  redirect_url text,
  transaction_id text,
  payment_type text,
  expires_at timestamptz not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.midtrans_payments
  add column if not exists user_id uuid,
  add column if not exists amount integer,
  add column if not exists snap_token text,
  add column if not exists transaction_id text,
  add column if not exists payment_type text,
  add column if not exists expires_at timestamptz,
  add column if not exists updated_at timestamptz not null default now();

update public.midtrans_payments as payment
set user_id = profile.id,
    amount = invoice.amount,
    expires_at = coalesce(
      payment.expires_at,
      payment.created_at + interval '24 hours'
    ),
    updated_at = coalesce(payment.updated_at, payment.created_at)
from public.invoices as invoice
join public.profiles as profile
  on profile.customer_id = invoice.customer_id
where payment.invoice_id = invoice.id
  and (
    payment.user_id is null
    or payment.amount is null
    or payment.expires_at is null
  );

do $$
begin
  if exists (
    select 1
    from public.midtrans_payments
    where user_id is null
      or amount is null
      or expires_at is null
  ) then
    raise exception
      'Cannot migrate Midtrans payments: an existing payment cannot be linked to an invoice owner.';
  end if;
end;
$$;

alter table public.midtrans_payments
  drop constraint if exists midtrans_payments_pkey,
  drop constraint if exists midtrans_payments_order_id_key,
  drop constraint if exists midtrans_payments_invoice_id_fkey,
  drop constraint if exists midtrans_payments_user_id_fkey,
  drop constraint if exists midtrans_payments_amount_check,
  drop constraint if exists midtrans_payments_status_check;

alter table public.midtrans_payments
  alter column user_id set not null,
  alter column amount set not null,
  alter column expires_at set not null,
  add constraint midtrans_payments_pkey primary key (order_id),
  add constraint midtrans_payments_invoice_id_fkey
    foreign key (invoice_id) references public.invoices(id) on delete restrict,
  add constraint midtrans_payments_user_id_fkey
    foreign key (user_id) references auth.users(id) on delete restrict,
  add constraint midtrans_payments_amount_check check (amount > 0),
  add constraint midtrans_payments_status_check
    check (status in ('creating', 'pending', 'paid', 'failed', 'expired', 'cancelled'));

create index if not exists midtrans_payments_user_created_idx
  on public.midtrans_payments(user_id, created_at desc);

create unique index if not exists midtrans_one_open_payment_per_invoice
  on public.midtrans_payments(invoice_id)
  where status in ('creating', 'pending');

alter table public.midtrans_payments enable row level security;
revoke all on public.midtrans_payments from public, anon, authenticated;
grant all on public.midtrans_payments to service_role;

insert into public.invoices (
  id,
  customer_id,
  period,
  amount,
  currency,
  status,
  due_at
)
select
  'INV-2026-10-001',
  customer.customer_id,
  'Oktober 2026',
  249000,
  'IDR',
  'unpaid',
  now() + interval '30 days'
from public.customers as customer
where customer.customer_id = '0012995'
on conflict (id) do nothing;
