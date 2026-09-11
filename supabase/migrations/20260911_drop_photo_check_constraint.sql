-- Migration: Drop check constraint on repair_photos.step_context

ALTER TABLE public.repair_photos 
DROP CONSTRAINT IF EXISTS repair_photos_step_context_check;
