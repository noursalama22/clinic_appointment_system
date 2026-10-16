BEGIN;

-- Refuse to install tenant rules over inconsistent existing data.
DO $preflight$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM public.profiles AS p
    WHERE p.role IN (
      'doctor'::public.user_role,
      'admin'::public.user_role
    )
      AND p.clinic_id IS NULL
  ) THEN
    RAISE EXCEPTION
      'Cannot enable tenant security: a doctor/admin profile has no clinic assignment';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.doctors AS d
    LEFT JOIN public.profiles AS p ON p.id = d.doctor_id
    WHERE d.clinic_id IS NULL
       OR p.id IS NULL
       OR p.role IS DISTINCT FROM 'doctor'::public.user_role
       OR p.clinic_id IS DISTINCT FROM d.clinic_id
  ) THEN
    RAISE EXCEPTION
      'Cannot enable tenant security: a doctor row has a missing, non-doctor, or mismatched profile';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.appointments AS a
    LEFT JOIN public.doctors AS d ON d.doctor_id = a.doctor_id
    LEFT JOIN public.profiles AS patient ON patient.id = a.patient_id
    WHERE a.clinic_id IS NULL
       OR d.doctor_id IS NULL
       OR patient.id IS NULL
       OR d.clinic_id IS DISTINCT FROM a.clinic_id
       OR patient.role IS DISTINCT FROM 'patient'::public.user_role
       OR (
         patient.clinic_id IS NOT NULL
         AND patient.clinic_id IS DISTINCT FROM a.clinic_id
       )
  ) THEN
    RAISE EXCEPTION
      'Cannot enable tenant security: an appointment has a missing or mismatched clinic assignment';
  END IF;
END;
$preflight$;

ALTER TABLE public.profiles
  ADD CONSTRAINT profiles_staff_requires_clinic
  CHECK (
    role = 'patient'::public.user_role
    OR clinic_id IS NOT NULL
  );

ALTER TABLE public.doctors
  ALTER COLUMN clinic_id SET NOT NULL;

ALTER TABLE public.appointments
  ALTER COLUMN clinic_id SET NOT NULL;

CREATE SCHEMA private AUTHORIZATION postgres;
REVOKE ALL ON SCHEMA private FROM PUBLIC, anon;
GRANT USAGE ON SCHEMA private TO authenticated;

CREATE FUNCTION private.current_role()
RETURNS public.user_role
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT p.role
  FROM public.profiles AS p
  WHERE p.id = (SELECT auth.uid())
$function$;

CREATE FUNCTION private.is_admin_for_clinic(p_clinic_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM public.profiles AS p
    WHERE p.id = (SELECT auth.uid())
      AND p.role = 'admin'::public.user_role
      AND p.clinic_id = p_clinic_id
  )
$function$;

CREATE FUNCTION private.can_read_profile(p_profile_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT
    p_profile_id = (SELECT auth.uid())
    OR EXISTS (
      SELECT 1
      FROM public.profiles AS viewer
      JOIN public.profiles AS target ON target.id = p_profile_id
      WHERE viewer.id = (SELECT auth.uid())
        AND (
          (
            viewer.role = 'admin'::public.user_role
            AND (
              target.clinic_id = viewer.clinic_id
              OR (
                target.role = 'patient'::public.user_role
                AND EXISTS (
                  SELECT 1
                  FROM public.appointments AS a
                  WHERE a.patient_id = target.id
                    AND a.clinic_id = viewer.clinic_id
                )
              )
            )
          )
          OR (
            viewer.role = 'doctor'::public.user_role
            AND target.role = 'patient'::public.user_role
            AND EXISTS (
              SELECT 1
              FROM public.appointments AS a
              WHERE a.patient_id = target.id
                AND a.doctor_id = viewer.id
            )
          )
        )
    )
$function$;

CREATE FUNCTION private.doctor_profile_matches_clinic(
  p_doctor_id uuid,
  p_clinic_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM public.profiles AS p
    WHERE p.id = p_doctor_id
      AND p.role = 'doctor'::public.user_role
      AND p.clinic_id = p_clinic_id
  )
$function$;

CREATE FUNCTION private.can_manage_doctor_schedule(p_doctor_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM public.doctors AS d
    WHERE d.doctor_id = p_doctor_id
      AND (
        (
          d.doctor_id = (SELECT auth.uid())
          AND private.current_role() = 'doctor'::public.user_role
        )
        OR private.is_admin_for_clinic(d.clinic_id)
      )
  )
$function$;

CREATE FUNCTION private.appointment_tenant_is_valid(
  p_patient_id uuid,
  p_doctor_id uuid,
  p_clinic_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM public.profiles AS patient
    JOIN public.doctors AS d ON d.doctor_id = p_doctor_id
    JOIN public.profiles AS doctor_profile ON doctor_profile.id = d.doctor_id
    WHERE patient.id = p_patient_id
      AND patient.role = 'patient'::public.user_role
      AND doctor_profile.role = 'doctor'::public.user_role
      AND d.clinic_id = p_clinic_id
      AND doctor_profile.clinic_id = p_clinic_id
      AND (
        patient.clinic_id IS NULL
        OR patient.clinic_id = p_clinic_id
      )
  )
$function$;

CREATE FUNCTION private.patient_can_book(
  p_patient_id uuid,
  p_clinic_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM public.profiles AS p
    WHERE p.id = p_patient_id
      AND p.id = (SELECT auth.uid())
      AND p.role = 'patient'::public.user_role
      AND (
        p.clinic_id IS NULL
        OR p.clinic_id = p_clinic_id
      )
  )
$function$;

CREATE FUNCTION private.is_trusted_writer()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT auth.role() IS NULL OR auth.role() = 'service_role'
$function$;

CREATE FUNCTION private.guard_profile_update()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF private.is_trusted_writer() THEN
    RETURN NEW;
  END IF;

  IF auth.role() <> 'authenticated'
    OR (SELECT auth.uid()) IS DISTINCT FROM OLD.id
    OR NEW.id IS DISTINCT FROM OLD.id
    OR NEW.role IS DISTINCT FROM OLD.role
    OR NEW.clinic_id IS DISTINCT FROM OLD.clinic_id
    OR NEW.created_at IS DISTINCT FROM OLD.created_at
    OR (
      NEW.email IS DISTINCT FROM OLD.email
      AND pg_catalog.current_setting('app.auth_email_sync', true) IS DISTINCT FROM 'on'
    )
  THEN
    RAISE EXCEPTION 'Profile fields are not writable by this user'
      USING ERRCODE = '42501';
  END IF;

  RETURN NEW;
END;
$function$;

CREATE TRIGGER profiles_00_guard_update
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW
  EXECUTE FUNCTION private.guard_profile_update();

CREATE FUNCTION private.sync_auth_email_to_profile()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_previous_sync_flag text;
BEGIN
  IF NEW.email IS NOT DISTINCT FROM OLD.email THEN
    RETURN NEW;
  END IF;

  v_previous_sync_flag :=
    pg_catalog.current_setting('app.auth_email_sync', true);
  PERFORM pg_catalog.set_config('app.auth_email_sync', 'on', true);

  UPDATE public.profiles
  SET email = NEW.email
  WHERE id = NEW.id;

  PERFORM pg_catalog.set_config(
    'app.auth_email_sync',
    COALESCE(v_previous_sync_flag, ''),
    true
  );

  RETURN NEW;
END;
$function$;

CREATE TRIGGER auth_user_email_updated
  AFTER UPDATE OF email ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION private.sync_auth_email_to_profile();

CREATE FUNCTION public.get_own_profile_email()
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT p.email
  FROM public.profiles AS p
  WHERE p.id = (SELECT auth.uid())
$function$;

REVOKE ALL ON FUNCTION public.get_own_profile_email() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_own_profile_email() TO authenticated;

CREATE FUNCTION private.assert_appointment_tenant(p_appointment_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM public.appointments AS a
    LEFT JOIN public.doctors AS d ON d.doctor_id = a.doctor_id
    LEFT JOIN public.profiles AS patient ON patient.id = a.patient_id
    LEFT JOIN public.profiles AS doctor_profile
      ON doctor_profile.id = a.doctor_id
    WHERE a.id = p_appointment_id
      AND (
        a.clinic_id IS NULL
        OR d.doctor_id IS NULL
        OR patient.id IS NULL
        OR doctor_profile.id IS NULL
        OR d.clinic_id IS DISTINCT FROM a.clinic_id
        OR doctor_profile.role IS DISTINCT FROM 'doctor'::public.user_role
        OR doctor_profile.clinic_id IS DISTINCT FROM a.clinic_id
        OR patient.role IS DISTINCT FROM 'patient'::public.user_role
        OR (
          patient.clinic_id IS NOT NULL
          AND patient.clinic_id IS DISTINCT FROM a.clinic_id
        )
      )
  ) THEN
    RAISE EXCEPTION 'Appointment clinic assignment is invalid'
      USING ERRCODE = '23514';
  END IF;
END;
$function$;

CREATE FUNCTION private.enforce_tenant_consistency()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_profile_id uuid;
  v_doctor_id uuid;
  v_appointment_id uuid;
  v_profile_role public.user_role;
  v_profile_clinic_id uuid;
BEGIN
  IF TG_TABLE_SCHEMA = 'public' AND TG_TABLE_NAME = 'profiles' THEN
    IF TG_OP = 'UPDATE' THEN
      IF NEW.role IS NOT DISTINCT FROM OLD.role
        AND NEW.clinic_id IS NOT DISTINCT FROM OLD.clinic_id
      THEN
        RETURN NULL;
      END IF;
    END IF;

    v_profile_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.id ELSE NEW.id END;

    IF TG_OP <> 'DELETE' THEN
      SELECT p.role, p.clinic_id
      INTO v_profile_role, v_profile_clinic_id
      FROM public.profiles AS p
      WHERE p.id = v_profile_id;

      IF FOUND
        AND v_profile_role IN (
          'doctor'::public.user_role,
          'admin'::public.user_role
        )
        AND v_profile_clinic_id IS NULL
      THEN
        RAISE EXCEPTION 'Doctor/admin profiles require a clinic assignment'
          USING ERRCODE = '23514';
      END IF;
    END IF;

    IF EXISTS (
      SELECT 1
      FROM public.doctors AS d
      LEFT JOIN public.profiles AS p ON p.id = d.doctor_id
      WHERE d.doctor_id = v_profile_id
        AND (
          p.role IS DISTINCT FROM 'doctor'::public.user_role
          OR p.clinic_id IS DISTINCT FROM d.clinic_id
        )
    ) THEN
      RAISE EXCEPTION 'Doctor record and profile clinic assignments must match'
        USING ERRCODE = '23514';
    END IF;

    FOR v_appointment_id IN
      SELECT a.id
      FROM public.appointments AS a
      WHERE a.patient_id = v_profile_id
    LOOP
      PERFORM private.assert_appointment_tenant(v_appointment_id);
    END LOOP;

    IF EXISTS (
      SELECT 1
      FROM public.appointments AS a
      WHERE a.doctor_id = v_profile_id
    ) THEN
      FOR v_appointment_id IN
        SELECT a.id
        FROM public.appointments AS a
        WHERE a.doctor_id = v_profile_id
      LOOP
        PERFORM private.assert_appointment_tenant(v_appointment_id);
      END LOOP;
    END IF;

    RETURN NULL;
  ELSIF TG_TABLE_SCHEMA = 'public' AND TG_TABLE_NAME = 'doctors' THEN
    IF TG_OP = 'UPDATE' THEN
      IF NEW.doctor_id IS NOT DISTINCT FROM OLD.doctor_id
        AND NEW.clinic_id IS NOT DISTINCT FROM OLD.clinic_id
      THEN
        RETURN NULL;
      END IF;
    END IF;

    v_doctor_id := CASE
      WHEN TG_OP = 'DELETE' THEN OLD.doctor_id
      ELSE NEW.doctor_id
    END;

    IF TG_OP <> 'DELETE'
      AND EXISTS (
        SELECT 1
        FROM public.doctors AS d
        LEFT JOIN public.profiles AS p ON p.id = d.doctor_id
        WHERE d.doctor_id = v_doctor_id
          AND (
            p.role IS DISTINCT FROM 'doctor'::public.user_role
            OR p.clinic_id IS DISTINCT FROM d.clinic_id
          )
      )
    THEN
      RAISE EXCEPTION 'Doctor record and profile clinic assignments must match'
        USING ERRCODE = '23514';
    END IF;

    FOR v_appointment_id IN
      SELECT a.id
      FROM public.appointments AS a
      WHERE a.doctor_id = v_doctor_id
    LOOP
      PERFORM private.assert_appointment_tenant(v_appointment_id);
    END LOOP;

    RETURN NULL;
  ELSE
    IF TG_OP = 'UPDATE' THEN
      IF NEW.patient_id IS NOT DISTINCT FROM OLD.patient_id
        AND NEW.doctor_id IS NOT DISTINCT FROM OLD.doctor_id
        AND NEW.clinic_id IS NOT DISTINCT FROM OLD.clinic_id
      THEN
        RETURN NULL;
      END IF;
    END IF;

    v_appointment_id := CASE
      WHEN TG_OP = 'DELETE' THEN OLD.id
      ELSE NEW.id
    END;
    PERFORM private.assert_appointment_tenant(v_appointment_id);
    RETURN NULL;
  END IF;
END;
$function$;

CREATE CONSTRAINT TRIGGER profiles_tenant_consistency
  AFTER INSERT OR UPDATE OR DELETE ON public.profiles
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION private.enforce_tenant_consistency();

CREATE CONSTRAINT TRIGGER doctors_tenant_consistency
  AFTER INSERT OR UPDATE OR DELETE ON public.doctors
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION private.enforce_tenant_consistency();

CREATE CONSTRAINT TRIGGER appointments_tenant_consistency
  AFTER INSERT OR UPDATE OR DELETE ON public.appointments
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION private.enforce_tenant_consistency();

CREATE FUNCTION private.guard_appointment_update()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_role public.user_role;
BEGIN
  IF private.is_trusted_writer() THEN
    RETURN NEW;
  END IF;

  v_role := private.current_role();

  IF NEW.id IS DISTINCT FROM OLD.id
    OR NEW.patient_id IS DISTINCT FROM OLD.patient_id
    OR NEW.doctor_id IS DISTINCT FROM OLD.doctor_id
    OR NEW.clinic_id IS DISTINCT FROM OLD.clinic_id
    OR NEW.created_at IS DISTINCT FROM OLD.created_at
  THEN
    RAISE EXCEPTION 'Appointment identity fields are immutable'
      USING ERRCODE = '42501';
  END IF;

  IF OLD.status NOT IN (
    'pending'::public.appointment_status,
    'confirmed'::public.appointment_status
  ) THEN
    RAISE EXCEPTION 'Cancelled/completed appointments cannot be modified'
      USING ERRCODE = '42501';
  END IF;

  IF v_role = 'patient'::public.user_role THEN
    IF OLD.patient_id IS DISTINCT FROM (SELECT auth.uid())
      OR NEW.status NOT IN (
        OLD.status,
        'cancelled'::public.appointment_status
      )
    THEN
      RAISE EXCEPTION 'Patients may only reschedule or cancel their own appointments'
        USING ERRCODE = '42501';
    END IF;
  ELSIF v_role = 'doctor'::public.user_role THEN
    IF OLD.doctor_id IS DISTINCT FROM (SELECT auth.uid())
      OR NEW.appointment_date IS DISTINCT FROM OLD.appointment_date
      OR NEW.start_time IS DISTINCT FROM OLD.start_time
      OR NEW.end_time IS DISTINCT FROM OLD.end_time
      OR (
        NEW.status IS DISTINCT FROM OLD.status
        AND NEW.status NOT IN (
          'confirmed'::public.appointment_status,
          'cancelled'::public.appointment_status,
          'completed'::public.appointment_status
        )
      )
    THEN
      RAISE EXCEPTION 'Doctors may only update status on assigned appointments'
        USING ERRCODE = '42501';
    END IF;
  ELSIF v_role = 'admin'::public.user_role THEN
    IF NOT private.is_admin_for_clinic(OLD.clinic_id)
      OR NEW.status NOT IN (
        OLD.status,
        'cancelled'::public.appointment_status
      )
    THEN
      RAISE EXCEPTION 'Clinic admins may only reschedule or cancel active clinic appointments'
        USING ERRCODE = '42501';
    END IF;
  ELSE
    RAISE EXCEPTION 'Role is not permitted to update appointments'
      USING ERRCODE = '42501';
  END IF;

  RETURN NEW;
END;
$function$;

CREATE TRIGGER appointments_00_actor_field_guard
  BEFORE UPDATE ON public.appointments
  FOR EACH ROW
  EXECUTE FUNCTION private.guard_appointment_update();

CREATE FUNCTION private.guard_appointment_delete()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF private.is_trusted_writer() THEN
    RETURN OLD;
  END IF;

  RAISE EXCEPTION 'Appointments cannot be deleted by client roles'
    USING ERRCODE = '42501';
END;
$function$;

CREATE TRIGGER appointments_00_no_client_delete
  BEFORE DELETE ON public.appointments
  FOR EACH ROW
  EXECUTE FUNCTION private.guard_appointment_delete();

REVOKE ALL ON ALL FUNCTIONS IN SCHEMA private FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.current_role() TO authenticated;
GRANT EXECUTE ON FUNCTION private.is_admin_for_clinic(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION private.can_read_profile(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION private.doctor_profile_matches_clinic(uuid, uuid)
  TO authenticated;
GRANT EXECUTE ON FUNCTION private.can_manage_doctor_schedule(uuid)
  TO authenticated;
GRANT EXECUTE ON FUNCTION private.appointment_tenant_is_valid(uuid, uuid, uuid)
  TO authenticated;
GRANT EXECUTE ON FUNCTION private.patient_can_book(uuid, uuid)
  TO authenticated;
REVOKE ALL ON TYPE public.user_role FROM PUBLIC, anon;
REVOKE ALL ON TYPE public.appointment_status FROM PUBLIC, anon;
GRANT USAGE ON TYPE public.user_role TO authenticated;
GRANT USAGE ON TYPE public.appointment_status TO authenticated;
GRANT USAGE ON TYPE public.user_role TO service_role;
GRANT USAGE ON TYPE public.appointment_status TO service_role;

REVOKE ALL ON TABLE
  public.clinics,
  public.profiles,
  public.doctors,
  public.working_hours,
  public.appointments
FROM PUBLIC, anon, authenticated;

GRANT USAGE ON SCHEMA public TO authenticated;
GRANT ALL ON TABLE
  public.clinics,
  public.profiles,
  public.doctors,
  public.working_hours,
  public.appointments
TO service_role;

GRANT SELECT ON public.clinics TO authenticated;
GRANT UPDATE (name, address) ON public.clinics TO authenticated;

GRANT SELECT (id, full_name, role, clinic_id, created_at)
  ON public.profiles TO authenticated;
GRANT UPDATE (full_name) ON public.profiles TO authenticated;

GRANT SELECT ON public.doctors TO authenticated;
GRANT INSERT (doctor_id, specialization, bio, clinic_id)
  ON public.doctors TO authenticated;
GRANT UPDATE (specialization, bio) ON public.doctors TO authenticated;

GRANT SELECT ON public.working_hours TO authenticated;
GRANT INSERT (doctor_id, day_of_week, start_time, end_time)
  ON public.working_hours TO authenticated;
GRANT UPDATE (day_of_week, start_time, end_time)
  ON public.working_hours TO authenticated;
GRANT DELETE ON public.working_hours TO authenticated;

GRANT SELECT ON public.appointments TO authenticated;
GRANT INSERT (
  patient_id,
  doctor_id,
  clinic_id,
  appointment_date,
  start_time,
  end_time,
  status
) ON public.appointments TO authenticated;
GRANT UPDATE (
  appointment_date,
  start_time,
  end_time,
  status
) ON public.appointments TO authenticated;

ALTER TABLE public.clinics ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.doctors ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.working_hours ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.appointments ENABLE ROW LEVEL SECURITY;

CREATE POLICY clinics_authenticated_read
  ON public.clinics
  FOR SELECT TO authenticated
  USING (true);

CREATE POLICY clinics_admin_update
  ON public.clinics
  FOR UPDATE TO authenticated
  USING (private.is_admin_for_clinic(id))
  WITH CHECK (private.is_admin_for_clinic(id));

CREATE POLICY profiles_scoped_read
  ON public.profiles
  FOR SELECT TO authenticated
  USING (private.can_read_profile(id));

CREATE POLICY profiles_self_update
  ON public.profiles
  FOR UPDATE TO authenticated
  USING (id = (SELECT auth.uid()))
  WITH CHECK (id = (SELECT auth.uid()));

CREATE POLICY doctors_authenticated_read
  ON public.doctors
  FOR SELECT TO authenticated
  USING (true);

CREATE POLICY doctors_admin_insert
  ON public.doctors
  FOR INSERT TO authenticated
  WITH CHECK (
    private.is_admin_for_clinic(clinic_id)
    AND private.doctor_profile_matches_clinic(doctor_id, clinic_id)
  );

CREATE POLICY doctors_admin_update
  ON public.doctors
  FOR UPDATE TO authenticated
  USING (private.is_admin_for_clinic(clinic_id))
  WITH CHECK (private.is_admin_for_clinic(clinic_id));

CREATE POLICY working_hours_authenticated_read
  ON public.working_hours
  FOR SELECT TO authenticated
  USING (true);

CREATE POLICY working_hours_authorized_insert
  ON public.working_hours
  FOR INSERT TO authenticated
  WITH CHECK (private.can_manage_doctor_schedule(doctor_id));

CREATE POLICY working_hours_authorized_update
  ON public.working_hours
  FOR UPDATE TO authenticated
  USING (private.can_manage_doctor_schedule(doctor_id))
  WITH CHECK (private.can_manage_doctor_schedule(doctor_id));

CREATE POLICY working_hours_authorized_delete
  ON public.working_hours
  FOR DELETE TO authenticated
  USING (private.can_manage_doctor_schedule(doctor_id));

CREATE POLICY appointments_scoped_read
  ON public.appointments
  FOR SELECT TO authenticated
  USING (
    (
      patient_id = (SELECT auth.uid())
      AND private.current_role() = 'patient'::public.user_role
    )
    OR (
      doctor_id = (SELECT auth.uid())
      AND private.current_role() = 'doctor'::public.user_role
    )
    OR private.is_admin_for_clinic(clinic_id)
  );

CREATE POLICY appointments_patient_insert
  ON public.appointments
  FOR INSERT TO authenticated
  WITH CHECK (
    status = 'pending'::public.appointment_status
    AND private.patient_can_book(patient_id, clinic_id)
    AND private.appointment_tenant_is_valid(patient_id, doctor_id, clinic_id)
  );

CREATE POLICY appointments_admin_insert
  ON public.appointments
  FOR INSERT TO authenticated
  WITH CHECK (
    status = 'pending'::public.appointment_status
    AND private.is_admin_for_clinic(clinic_id)
    AND private.appointment_tenant_is_valid(patient_id, doctor_id, clinic_id)
  );

CREATE POLICY appointments_patient_update
  ON public.appointments
  FOR UPDATE TO authenticated
  USING (
    patient_id = (SELECT auth.uid())
    AND private.current_role() = 'patient'::public.user_role
    AND status IN (
      'pending'::public.appointment_status,
      'confirmed'::public.appointment_status
    )
  )
  WITH CHECK (
    patient_id = (SELECT auth.uid())
    AND private.current_role() = 'patient'::public.user_role
    AND private.appointment_tenant_is_valid(patient_id, doctor_id, clinic_id)
  );

CREATE POLICY appointments_doctor_update
  ON public.appointments
  FOR UPDATE TO authenticated
  USING (
    doctor_id = (SELECT auth.uid())
    AND private.current_role() = 'doctor'::public.user_role
  )
  WITH CHECK (
    doctor_id = (SELECT auth.uid())
    AND private.current_role() = 'doctor'::public.user_role
    AND private.appointment_tenant_is_valid(patient_id, doctor_id, clinic_id)
  );

CREATE POLICY appointments_admin_update
  ON public.appointments
  FOR UPDATE TO authenticated
  USING (
    private.is_admin_for_clinic(clinic_id)
    AND status IN (
      'pending'::public.appointment_status,
      'confirmed'::public.appointment_status
    )
  )
  WITH CHECK (
    private.is_admin_for_clinic(clinic_id)
    AND private.appointment_tenant_is_valid(patient_id, doctor_id, clinic_id)
  );

COMMIT;
