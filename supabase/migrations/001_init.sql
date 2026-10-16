-- Initial multi-tenant clinic schema.
-- Auth signup and appointment lifecycle triggers, overlap prevention, grants, and RLS
-- are intentionally managed by later approved migrations.

CREATE TYPE public.user_role AS ENUM (
  'patient',
  'doctor',
  'admin'
);

CREATE TYPE public.appointment_status AS ENUM (
  'pending',
  'confirmed',
  'cancelled',
  'completed'
);

CREATE TABLE public.clinics (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  address text,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE public.profiles (
  id uuid PRIMARY KEY
    REFERENCES auth.users (id) ON DELETE CASCADE,
  email text NOT NULL,
  full_name text,
  role public.user_role NOT NULL DEFAULT 'patient',
  clinic_id uuid
    REFERENCES public.clinics (id),
  created_at timestamptz DEFAULT now()
);

CREATE TABLE public.doctors (
  doctor_id uuid PRIMARY KEY
    REFERENCES public.profiles (id) ON DELETE CASCADE,
  specialization text,
  bio text,
  clinic_id uuid
    REFERENCES public.clinics (id),
  created_at timestamptz DEFAULT now()
);

CREATE TABLE public.working_hours (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  doctor_id uuid NOT NULL
    REFERENCES public.doctors (doctor_id) ON DELETE CASCADE,
  day_of_week integer NOT NULL,
  start_time time NOT NULL,
  end_time time NOT NULL,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE public.appointments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id uuid NOT NULL
    REFERENCES public.profiles (id) ON DELETE CASCADE,
  doctor_id uuid NOT NULL
    REFERENCES public.doctors (doctor_id) ON DELETE CASCADE,
  clinic_id uuid
    REFERENCES public.clinics (id),
  appointment_date date NOT NULL,
  start_time time NOT NULL,
  end_time time NOT NULL,
  status public.appointment_status NOT NULL DEFAULT 'pending',
  created_at timestamptz DEFAULT now()
);

CREATE INDEX profiles_clinic_id_idx
  ON public.profiles (clinic_id);

CREATE INDEX doctors_clinic_id_idx
  ON public.doctors (clinic_id);

CREATE INDEX working_hours_doctor_id_idx
  ON public.working_hours (doctor_id);

CREATE INDEX appointments_patient_id_idx
  ON public.appointments (patient_id);

CREATE INDEX appointments_doctor_id_idx
  ON public.appointments (doctor_id);

CREATE INDEX appointments_clinic_id_idx
  ON public.appointments (clinic_id);
