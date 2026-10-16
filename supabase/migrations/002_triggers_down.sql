-- Rollback for 002_triggers.sql. Run only when intentionally removing these guards.
DROP TRIGGER on_auth_user_created ON auth.users;
DROP TRIGGER appointments_status_transition_guard ON public.appointments;

DROP FUNCTION public.handle_new_user();
DROP FUNCTION public.validate_appointment_status_transition();
