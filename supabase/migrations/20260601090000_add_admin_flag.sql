-- Add is_admin column to profiles
ALTER TABLE public.profiles ADD COLUMN is_admin BOOLEAN NOT NULL DEFAULT false;

-- Register admin users
UPDATE public.profiles SET is_admin = true WHERE email IN ('triloks34@gmail.com', 'mr.engineer5000@gmail.com');
