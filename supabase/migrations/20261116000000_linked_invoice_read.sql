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
