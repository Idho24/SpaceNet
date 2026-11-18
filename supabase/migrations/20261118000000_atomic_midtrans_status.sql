-- Only the server may apply statuses already verified against Midtrans.
create or replace function public.apply_verified_midtrans_status(
  p_order_id text, p_amount numeric, p_status text,
  p_transaction_id text, p_payment_type text
) returns text
language plpgsql security invoker set search_path = ''
as $$
declare
  payment public.midtrans_payments%rowtype;
  invoice public.invoices%rowtype;
  next_status text;
begin
  if p_status is null or p_status not in ('pending','paid','failed','expired','cancelled') then
    raise exception 'Unsupported payment status';
  end if;
  select * into payment from public.midtrans_payments
    where order_id = p_order_id for update;
  if not found then raise exception 'Payment order was not found'; end if;
  if p_amount is null or p_amount <> payment.amount then
    raise exception 'Payment amount does not match';
  end if;
  select * into invoice from public.invoices where id = payment.invoice_id for update;
  if not found then raise exception 'Invoice was not found'; end if;
  if invoice.amount <> payment.amount or invoice.currency <> 'IDR' then
    raise exception 'Invoice amount or currency does not match';
  end if;
  -- Late pending/expired callbacks cannot undo an already verified settlement.
  next_status := case when payment.status = 'paid' then 'paid' else p_status end;
  update public.midtrans_payments set
    status = next_status,
    transaction_id = coalesce(nullif(p_transaction_id, ''), transaction_id),
    payment_type = coalesce(nullif(p_payment_type, ''), payment_type),
    updated_at = now()
    where order_id = p_order_id;
  if next_status = 'paid' then
    update public.invoices set status = 'paid',
      paid_at = coalesce(paid_at, now()), updated_at = now()
      where id = payment.invoice_id;
  end if;
  return next_status;
end;
$$;
revoke all on function public.apply_verified_midtrans_status(text,numeric,text,text,text) from public, anon, authenticated;
grant execute on function public.apply_verified_midtrans_status(text,numeric,text,text,text) to service_role;
