begin;
do $test$
declare
  source_payment public.midtrans_payments%rowtype;
  fixture_order text := 'TEST-' || gen_random_uuid()::text;
  fixture_invoice text := 'TEST-' || gen_random_uuid()::text;
  customer text;
  baseline timestamptz := '2027-01-31 15:59:59+00';
  expires timestamptz;
begin
  select p.* into source_payment from public.midtrans_payments p
    join public.invoices i on i.id=p.invoice_id
    join public.profiles pr on pr.customer_id=i.customer_id and pr.id=p.user_id
    where p.status='paid' limit 1;
  if not found then raise exception 'No verified fixture source'; end if;
  select customer_id into customer from public.invoices where id=source_payment.invoice_id;
  update public.customers set expiry_date=baseline where customer_id=customer;
  insert into public.invoices(id,customer_id,amount,period,due_at,status)
    values(fixture_invoice,customer,170000,'Test',now(),'unpaid');
  insert into public.midtrans_payments(order_id,invoice_id,user_id,amount,status,expires_at)
    values(fixture_order,fixture_invoice,source_payment.user_id,170000,'pending',now()+interval '1 day');
  -- An unverified invoice status alone must never renew.
  update public.invoices set status='paid' where id=fixture_invoice;
  if (select expiry_date from public.customers where customer_id=customer) <> baseline then
    raise exception 'Unverified invoice extended subscription';
  end if;
  update public.invoices set status='unpaid' where id=fixture_invoice;
  set local role service_role;
  perform public.apply_verified_midtrans_status(fixture_order,170000,'paid','test-renewal','dana');
  select expiry_date into expires from public.customers where customer_id=customer;
  if expires <> '2027-02-28 15:59:59+00'::timestamptz then
    raise exception 'Calendar month renewal incorrect: %',expires;
  end if;
  if (select renewal_applied_at from public.invoices where id=fixture_invoice) is null then
    raise exception 'Renewal marker missing';
  end if;
  perform public.apply_verified_midtrans_status(fixture_order,170000,'paid','test-renewal','dana');
  perform public.apply_verified_midtrans_status(fixture_order,170000,'pending',null,null);
  if (select expiry_date from public.customers where customer_id=customer) <> expires then
    raise exception 'Duplicate notification extended twice';
  end if;
  perform set_config('request.jwt.claim.sub',source_payment.user_id::text,true);
  if not exists(select 1 from public.get_my_payment_history() where order_id=fixture_order) then
    raise exception 'Owner cannot see payment history';
  end if;
  perform set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
  if exists(select 1 from public.get_my_payment_history()) then
    raise exception 'Another user can read history';
  end if;
  if has_function_privilege('anon','public.get_my_payment_history()','execute') then
    raise exception 'Anonymous history access is enabled';
  end if;
end;
$test$;
rollback;
select 'PASS: verified-only renewal, month-end, once per invoice, owner-scoped history; all fixtures rolled back' result;
