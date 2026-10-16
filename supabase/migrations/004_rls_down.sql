BEGIN;

DROP POLICY appointments_admin_update ON public.appointments;
DROP POLICY appointments_doctor_update ON public.appointments;
DROP POLICY appointments_patient_update ON public.appointments;
DROP POLICY appointments_admin_insert ON public.appointments;
DROP POLICY appointments_patient_insert ON public.appointments;
DROP POLICY appointments_scoped_read ON public.appointments;
DROP POLICY working_hours_authorized_delete ON public.working_hours;
DROP POLICY working_hours_authorized_update ON public.working_hours;
DROP POLICY working_hours_authorized_insert ON public.working_hours;
DROP POLICY working_hours_authenticated_read ON public.working_hours;
DROP POLICY doctors_admin_update ON public.doctors;
DROP POLICY doctors_admin_insert ON public.doctors;
DROP POLICY doctors_authenticated_read ON public.doctors;
DROP POLICY profiles_self_update ON public.profiles;
DROP POLICY profiles_scoped_read ON public.profiles;
DROP POLICY clinics_admin_update ON public.clinics;
DROP POLICY clinics_authenticated_read ON public.clinics;

DROP TRIGGER appointments_00_no_client_delete ON public.appointments;
DROP TRIGGER appointments_00_actor_field_guard ON public.appointments;
DROP TRIGGER appointments_tenant_consistency ON public.appointments;
DROP TRIGGER doctors_tenant_consistency ON public.doctors;
DROP TRIGGER profiles_tenant_consistency ON public.profiles;
DROP TRIGGER auth_user_email_updated ON auth.users;
DROP TRIGGER profiles_00_guard_update ON public.profiles;

REVOKE ALL ON TABLE
  public.clinics,
  public.profiles,
  public.doctors,
  public.working_hours,
  public.appointments
FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON TYPE public.user_role FROM authenticated, service_role;
REVOKE ALL ON TYPE public.appointment_status FROM authenticated, service_role;
GRANT USAGE ON TYPE public.user_role TO PUBLIC;
GRANT USAGE ON TYPE public.appointment_status TO PUBLIC;

ALTER TABLE public.clinics DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.profiles DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.doctors DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.working_hours DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.appointments DISABLE ROW LEVEL SECURITY;

ALTER TABLE public.appointments
  ALTER COLUMN clinic_id DROP NOT NULL;
ALTER TABLE public.doctors
  ALTER COLUMN clinic_id DROP NOT NULL;
ALTER TABLE public.profiles
  DROP CONSTRAINT profiles_staff_requires_clinic;

DROP FUNCTION public.get_own_profile_email();
DROP FUNCTION private.enforce_tenant_consistency();
DROP FUNCTION private.assert_appointment_tenant(uuid);
DROP FUNCTION private.guard_appointment_delete();
DROP FUNCTION private.guard_appointment_update();
DROP FUNCTION private.sync_auth_email_to_profile();
DROP FUNCTION private.guard_profile_update();
DROP FUNCTION private.is_trusted_writer();
DROP FUNCTION private.patient_can_book(uuid, uuid);
DROP FUNCTION private.appointment_tenant_is_valid(uuid, uuid, uuid);
DROP FUNCTION private.can_manage_doctor_schedule(uuid);
DROP FUNCTION private.doctor_profile_matches_clinic(uuid, uuid);
DROP FUNCTION private.can_read_profile(uuid);
DROP FUNCTION private.is_admin_for_clinic(uuid);
DROP FUNCTION private.current_role();

DROP SCHEMA private;

COMMIT;
