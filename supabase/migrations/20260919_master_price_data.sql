-- =============================================================================
-- Migration: Overwrite pricing_rules with master data
-- =============================================================================

-- Clear existing data
TRUNCATE TABLE public.pricing_rules;

-- Insert master data
INSERT INTO public.pricing_rules (panel_id, panel_name, base_rate, severity_min, severity_max)
VALUES
-- Depan
('PANEL_FRONT_BUMP', 'Bumper Depan', 500500, 1.5, 2.0),
('PANEL_FRONT_SPOIL', 'Spoiler Bumper depan', 286000, 1.5, 2.0),
('PANEL_HOOD_ENG', 'Kap Mesin', 715000, 1.5, 2.0),

-- Belakang
('PANEL_REAR_BUMP', 'Bumper Belakang', 500500, 1.5, 2.0),
('PANEL_REAR_SPOIL', 'Spoiler Bumper Belakang', 286000, 1.5, 2.0),
('PANEL_TRUNK', 'Bagasi', 643500, 1.5, 2.0),
('PANEL_TRUNK_SPOIL', 'Spoiler Bagasi', 286000, 1.5, 2.0),

-- Kanan (RH)
('PANEL_FENDER_FR_RH', 'Fender RH', 572000, 1.5, 2.0),
('PANEL_DOOR_FR_RH', 'Pintu Depan RH', 572000, 1.5, 2.0),
('PANEL_MIRROR_RH', 'Spion RH', 143000, 1.5, 2.0),
('PANEL_DOOR_RR_RH', 'Pintu Belakang RH', 572000, 1.5, 2.0),
('PANEL_QUARTER_RH', 'Quarter RH', 572000, 1.5, 2.0),
('PANEL_TRISPLANG_RH', 'Trisplang RH', 357500, 1.5, 2.0),
('PANEL_SIDE_ROOF_RH', 'Side Roof RH', 357500, 1.5, 2.0),

-- Kiri (LH)
('PANEL_FENDER_FR_LH', 'Fender LH', 572000, 1.5, 2.0),
('PANEL_DOOR_FR_LH', 'Pintu Depan LH', 572000, 1.5, 2.0),
('PANEL_MIRROR_LH', 'Spion LH', 143000, 1.5, 2.0),
('PANEL_DOOR_RR_LH', 'Pintu Belakang LH', 572000, 1.5, 2.0),
('PANEL_QUARTER_LH', 'Quarter LH', 572000, 1.5, 2.0),
('PANEL_TRISPLANG_LH', 'Trisplang LH', 357500, 1.5, 2.0),
('PANEL_SIDE_ROOF_LH', 'Side Roof LH', 357500, 1.5, 2.0),

-- Atap & Lainnya
('PANEL_ROOF', 'Roof', 1001000, 1.5, 2.0),
('PANEL_COVER', 'Cover', 286000, 1.5, 2.0);