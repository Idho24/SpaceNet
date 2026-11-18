DO $$
DECLARE
  v_unmatched_packages integer;
  v_unmatched_customers integer;
  v_candidates integer;
  v_inserted integer;
BEGIN
  PERFORM set_config('TimeZone', 'Asia/Jakarta', true);

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'billing_packages'
      AND column_name = 'monthly_fee'
  ) THEN
    RAISE EXCEPTION 'public.billing_packages.monthly_fee is required.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'customers'
      AND column_name IN ('active_package', 'installation_date', 'monthly_fee')
    GROUP BY table_name
    HAVING count(DISTINCT column_name) = 3
  ) THEN
    RAISE EXCEPTION
      'public.customers must have active_package, installation_date, and monthly_fee.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'invoices'
      AND column_name IN ('id', 'customer_id', 'period', 'amount', 'currency', 'status', 'due_at')
    GROUP BY table_name
    HAVING count(DISTINCT column_name) = 7
  ) THEN
    RAISE EXCEPTION 'public.invoices is missing required invoice columns.';
  END IF;

  WITH fee_plan(package_pattern, monthly_fee) AS (
    VALUES
      ('basic.*10mbps', 150000),
      ('gamer.*100mbps', 350000),
      ('home.*20mbps', 170000),
      ('pro.*50mbps', 220000)
  )
  SELECT count(*)
    INTO v_unmatched_packages
    FROM fee_plan AS fee
   WHERE (
     SELECT count(*)
       FROM public.billing_packages AS package
      WHERE regexp_replace(
        lower(coalesce(
          to_jsonb(package)->>'name',
          to_jsonb(package)->>'package_name',
          to_jsonb(package)->>'title',
          to_jsonb(package)->>'package',
          ''
        )),
        '[^a-z0-9]',
        '',
        'g'
      ) ~ fee.package_pattern
   ) <> 1;

  IF v_unmatched_packages > 0 THEN
    RAISE EXCEPTION
      'Each expected package must match exactly one billing_packages row; no changes were applied.';
  END IF;

  WITH fee_plan(package_pattern, monthly_fee) AS (
    VALUES
      ('basic.*10mbps', 150000),
      ('gamer.*100mbps', 350000),
      ('home.*20mbps', 170000),
      ('pro.*50mbps', 220000)
  )
  SELECT count(*)
    INTO v_unmatched_customers
    FROM public.customers AS customer
   WHERE NOT EXISTS (
     SELECT 1
       FROM fee_plan AS fee
      WHERE regexp_replace(
        lower(customer.active_package),
        '[^a-z0-9]',
        '',
        'g'
      ) ~ fee.package_pattern
   );

  IF v_unmatched_customers > 0 THEN
    RAISE EXCEPTION
      '% customer rows have an unrecognized package; no changes were applied.',
      v_unmatched_customers;
  END IF;

  WITH fee_plan(package_pattern, monthly_fee) AS (
    VALUES
      ('basic.*10mbps', 150000),
      ('gamer.*100mbps', 350000),
      ('home.*20mbps', 170000),
      ('pro.*50mbps', 220000)
  )
  UPDATE public.billing_packages AS package
     SET monthly_fee = fee.monthly_fee
    FROM fee_plan AS fee
   WHERE regexp_replace(
     lower(coalesce(
       to_jsonb(package)->>'name',
       to_jsonb(package)->>'package_name',
       to_jsonb(package)->>'title',
       to_jsonb(package)->>'package',
       ''
     )),
     '[^a-z0-9]',
     '',
     'g'
   ) ~ fee.package_pattern;

  WITH fee_plan(package_pattern, monthly_fee) AS (
    VALUES
      ('basic.*10mbps', 150000),
      ('gamer.*100mbps', 350000),
      ('home.*20mbps', 170000),
      ('pro.*50mbps', 220000)
  )
  UPDATE public.customers AS customer
     SET monthly_fee = fee.monthly_fee
    FROM fee_plan AS fee
   WHERE regexp_replace(
     lower(customer.active_package),
     '[^a-z0-9]',
     '',
     'g'
   ) ~ fee.package_pattern;

  WITH fee_plan(package_pattern, monthly_fee) AS (
    VALUES
      ('basic.*10mbps', 150000),
      ('gamer.*100mbps', 350000),
      ('home.*20mbps', 170000),
      ('pro.*50mbps', 220000)
  ),
  customer_fees AS (
    SELECT
      customer.customer_id,
      fee.monthly_fee,
      extract(
        day FROM (customer.installation_date AT TIME ZONE 'Asia/Jakarta')
      )::integer AS billing_day
    FROM public.customers AS customer
    JOIN fee_plan AS fee
      ON regexp_replace(
        lower(customer.active_package),
        '[^a-z0-9]',
        '',
        'g'
      ) ~ fee.package_pattern
  ),
  month_starts AS (
    SELECT
      customer_id,
      monthly_fee,
      billing_day,
      date_trunc('month', current_date)::date AS this_month,
      (date_trunc('month', current_date) + interval '1 month')::date AS next_month
    FROM customer_fees
  ),
  due_dates AS (
    SELECT
      customer_id,
      monthly_fee,
      make_date(
        extract(year FROM this_month)::integer,
        extract(month FROM this_month)::integer,
        least(
          billing_day,
          extract(day FROM (this_month + interval '1 month' - interval '1 day'))::integer
        )
      ) AS due_this_month,
      make_date(
        extract(year FROM next_month)::integer,
        extract(month FROM next_month)::integer,
        least(
          billing_day,
          extract(day FROM (next_month + interval '1 month' - interval '1 day'))::integer
        )
      ) AS due_next_month
    FROM month_starts
  ),
  scheduled AS (
    SELECT
      customer_id,
      monthly_fee,
      CASE
        WHEN due_this_month >= current_date THEN due_this_month
        ELSE due_next_month
      END AS due_on
    FROM due_dates
  ),
  candidates AS (
    SELECT
      customer_id,
      monthly_fee AS amount,
      due_on,
      format('INV-%s-%s', to_char(due_on, 'YYYYMM'), customer_id) AS id,
      CASE extract(month FROM due_on)::integer
        WHEN 1 THEN 'Januari'
        WHEN 2 THEN 'Februari'
        WHEN 3 THEN 'Maret'
        WHEN 4 THEN 'April'
        WHEN 5 THEN 'Mei'
        WHEN 6 THEN 'Juni'
        WHEN 7 THEN 'Juli'
        WHEN 8 THEN 'Agustus'
        WHEN 9 THEN 'September'
        WHEN 10 THEN 'Oktober'
        WHEN 11 THEN 'November'
        WHEN 12 THEN 'Desember'
      END || ' ' || extract(year FROM due_on)::integer::text AS period
    FROM scheduled
  ),
  inserted AS (
    INSERT INTO public.invoices (
      id,
      customer_id,
      period,
      amount,
      currency,
      status,
      due_at
    )
    SELECT
      candidate.id,
      candidate.customer_id,
      candidate.period,
      candidate.amount,
      'IDR',
      'unpaid',
      (candidate.due_on + time '23:59:59') AT TIME ZONE 'Asia/Jakarta'
    FROM candidates AS candidate
    WHERE NOT EXISTS (
      SELECT 1
        FROM public.invoices AS existing
       WHERE existing.customer_id = candidate.customer_id
         AND existing.period = candidate.period
    )
    ON CONFLICT (id) DO NOTHING
    RETURNING id
  )
  SELECT
    (SELECT count(*)::integer FROM candidates),
    (SELECT count(*)::integer FROM inserted)
    INTO v_candidates, v_inserted;

  IF v_candidates = 0 THEN
    RAISE EXCEPTION 'No current-cycle invoice candidates were found.';
  END IF;

  RAISE NOTICE
    'Prepared % customer invoices; inserted % new invoices. Existing customer-period invoices were left unchanged.',
    v_candidates,
    v_inserted;
END;
$$;
