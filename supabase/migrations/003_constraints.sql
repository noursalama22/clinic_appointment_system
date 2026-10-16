-- Validate weekly working-hour and appointment intervals.
BEGIN;

ALTER TABLE public.working_hours
  ADD CONSTRAINT working_hours_day_of_week_check
    CHECK (day_of_week BETWEEN 0 AND 6),
  ADD CONSTRAINT working_hours_time_order_check
    CHECK (end_time > start_time);

ALTER TABLE public.appointments
  ADD CONSTRAINT appointments_time_order_check
    CHECK (end_time > start_time);

-- btree_gist supplies GiST equality support for doctor_id alongside range overlap.
CREATE EXTENSION IF NOT EXISTS btree_gist;

-- Treat appointment intervals as half-open so adjacent bookings are valid.
-- Only pending and confirmed appointments reserve a doctor's time.
ALTER TABLE public.appointments
  ADD CONSTRAINT appointments_no_active_overlap
  EXCLUDE USING gist (
    doctor_id WITH =,
    (tsrange(
      appointment_date + start_time,
      appointment_date + end_time,
      '[)'
    )) WITH &&
  )
  WHERE (status IN (
    'pending'::public.appointment_status,
    'confirmed'::public.appointment_status
  ));

COMMIT;
