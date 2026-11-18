alter table public.invoices
  add column if not exists renewal_applied_at timestamptz,
  add column if not exists subscription_expires_at timestamptz;

create or replace function public.renew_subscription_for_paid_invoice()
returns trigger language plpgsql security invoker set search_path = ''
as $$
declare
  current_expiry timestamptz;
  new_expiry timestamptz;
begin
  if new.status <> 'paid' or new.renewal_applied_at is not null then
    return new;
  end if;
  -- A client redirect or manually changed invoice is not payment evidence.
  if not exists (
    select 1 from public.midtrans_payments p
    where p.invoice_id = new.id and p.status = 'paid' and p.amount = new.amount
  ) then return new; end if;
  select expiry_date into current_expiry from public.customers
    where customer_id = new.customer_id for update;
  if not found then raise exception 'Customer was not found'; end if;
  -- Calendar month in the customer's billing timezone; PostgreSQL clamps month ends.
  new_expiry := ((greatest(current_expiry, coalesce(new.paid_at, now()))
    at time zone 'Asia/Makassar') + interval '1 month') at time zone 'Asia/Makassar';
  update public.customers set expiry_date = new_expiry,
    subscription_status = 'active', updated_at = now()
    where customer_id = new.customer_id;
  new.subscription_expires_at := new_expiry;
  new.renewal_applied_at := now();
  return new;
end;
$$;
revoke all on function public.renew_subscription_for_paid_invoice() from public,anon,authenticated;
create trigger invoices_renew_verified_subscription
before insert or update of status on public.invoices
for each row execute function public.renew_subscription_for_paid_invoice();

create or replace function public.get_my_payment_history()
returns table (
  order_id text, invoice_id text, amount integer, payment_type text,
  transaction_id text, paid_at timestamptz, subscription_expires_at timestamptz
)
language sql stable security definer set search_path = ''
as $$
  select p.order_id,p.invoice_id,p.amount,p.payment_type,p.transaction_id,
    i.paid_at,i.subscription_expires_at
  from public.midtrans_payments p
  join public.invoices i on i.id=p.invoice_id
  join public.profiles pr on pr.customer_id=i.customer_id
  where pr.id=(select auth.uid()) and p.user_id=(select auth.uid())
    and p.status='paid' and i.status='paid'
  order by i.paid_at desc,p.order_id;
$$;
revoke all on function public.get_my_payment_history() from public,anon;
grant execute on function public.get_my_payment_history() to authenticated;

-- Repair only already-verified settlements, in payment order, once per invoice.
do $$
declare item record;
begin
  for item in
    select i.id from public.invoices i
    where i.status='paid' and i.renewal_applied_at is null
      and exists(select 1 from public.midtrans_payments p
        where p.invoice_id=i.id and p.status='paid' and p.amount=i.amount)
    order by i.paid_at,i.id
  loop
    update public.invoices set status='paid' where id=item.id;
  end loop;
end;
$$;
