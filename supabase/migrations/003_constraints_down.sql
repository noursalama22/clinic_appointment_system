-- Rollback for 003_constraints.sql.
-- Keep btree_gist installed; other objects may depend on the extension.
BEGIN;

ALTER TABLE public.appointments
  DROP CONSTRAINT appointments_no_active_overlap,
  DROP CONSTRAINT appointments_time_order_check;

ALTER TABLE public.working_hours
  DROP CONSTRAINT working_hours_day_of_week_check,
  DROP CONSTRAINT working_hours_time_order_check;

COMMIT;
