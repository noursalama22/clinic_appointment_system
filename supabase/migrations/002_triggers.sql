-- Create a patient profile for each new Supabase Auth user.
-- The role is deliberately fixed; user metadata cannot assign elevated roles.
CREATE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  INSERT INTO public.profiles (
    id,
    email,
    full_name,
    role
  )
  VALUES (
    NEW.id,
    NEW.email,
    NEW.raw_user_meta_data ->> 'full_name',
    'patient'::public.user_role
  );

  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public.handle_new_user()
  FROM PUBLIC, anon, authenticated;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();

-- Enforce the appointment lifecycle on every status-changing update.
CREATE FUNCTION public.validate_appointment_status_transition()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $function$
BEGIN
  IF NEW.status IS NOT DISTINCT FROM OLD.status THEN
    RETURN NEW;
  END IF;

  IF NOT (
    (
      OLD.status = 'pending'::public.appointment_status
      AND NEW.status IN (
        'confirmed'::public.appointment_status,
        'cancelled'::public.appointment_status
      )
    )
    OR
    (
      OLD.status = 'confirmed'::public.appointment_status
      AND NEW.status IN (
        'cancelled'::public.appointment_status,
        'completed'::public.appointment_status
      )
    )
  ) THEN
    RAISE EXCEPTION 'Invalid appointment status transition: % -> %',
      OLD.status,
      NEW.status
      USING ERRCODE = '23514';
  END IF;

  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public.validate_appointment_status_transition()
  FROM PUBLIC, anon, authenticated;

CREATE TRIGGER appointments_status_transition_guard
  BEFORE UPDATE ON public.appointments
  FOR EACH ROW
  EXECUTE FUNCTION public.validate_appointment_status_transition();
