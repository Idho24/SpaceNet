begin;
do $test$
declare
  fixture_order text := 'TEST-' || gen_random_uuid()::text;
  fixture_invoice text := 'TEST-' || gen_random_uuid()::text;
  source_payment public.midtrans_payments%rowtype;
  paid_time timestamptz;
begin
  select * into source_payment from public.midtrans_payments limit 1;
  if not found then raise exception 'No source fixture available'; end if;
  insert into public.invoices(id,customer_id,amount,currency,period,due_at,status)
    select fixture_invoice,customer_id,170000,'IDR',period,due_at,'unpaid'
    from public.invoices where id=source_payment.invoice_id;
  insert into public.midtrans_payments(order_id,invoice_id,user_id,amount,status,expires_at)
    values(fixture_order,fixture_invoice,source_payment.user_id,170000,'pending',now()+interval '1 day');
  begin
    perform public.apply_verified_midtrans_status(fixture_order,170000.4,'paid','test-tx','dana');
    raise exception 'Expected amount validation' using errcode='ZX001';
  exception when others then
    if sqlstate='ZX001' then raise; end if;
  end;
  if (select status from public.midtrans_payments where order_id=fixture_order)<>'pending' then
    raise exception 'Amount mismatch changed payment';
  end if;
  perform public.apply_verified_midtrans_status(fixture_order,170000,'paid','test-tx','dana');
  if (select status from public.invoices where id=fixture_invoice)<>'paid' then
    raise exception 'Invoice did not settle';
  end if;
  select paid_at into paid_time from public.invoices where id=fixture_invoice;
  if paid_time is null then raise exception 'Missing paid timestamp'; end if;
  perform public.apply_verified_midtrans_status(fixture_order,170000,'pending',null,null);
  if (select status from public.midtrans_payments where order_id=fixture_order)<>'paid' then
    raise exception 'Late callback downgraded payment';
  end if;
  if (select paid_at from public.invoices where id=fixture_invoice) is distinct from paid_time then
    raise exception 'Duplicate callback changed paid timestamp';
  end if;
  -- Repair a historical partial update when the verified callback is retried.
  update public.invoices set status='unpaid',paid_at=null where id=fixture_invoice;
  perform public.apply_verified_midtrans_status(fixture_order,170000,'paid','test-tx','dana');
  if (select status from public.invoices where id=fixture_invoice)<>'paid' then
    raise exception 'Retry did not repair invoice';
  end if;
  if has_function_privilege('anon','public.apply_verified_midtrans_status(text,numeric,text,text,text)','EXECUTE')
    or has_function_privilege('authenticated','public.apply_verified_midtrans_status(text,numeric,text,text,text)','EXECUTE') then
    raise exception 'Client role can apply payment statuses';
  end if;
end;
$test$;
rollback;
select 'PASS: amount validation, atomic settlement, duplicate callbacks, repair, service-only access; fixture rolled back' as result;