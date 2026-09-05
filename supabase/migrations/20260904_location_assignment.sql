DO $ $
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'service_area_enum') THEN
        CREATE TYPE public.service_area_enum AS ENUM (
            'Bandung', 'Cimahi', 'Soreang', 
            'Jakarta Pusat', 'Jakarta Utara', 'Jakarta Timur', 'Jakarta Selatan', 'Jakarta Barat', 
            'Bogor', 'Depok', 'Tangerang', 'Bekasi'
        );
    END IF;
END$ $;

ALTER TABLE public.partners ADD COLUMN IF NOT EXISTS service_area public.service_area_enum;
ALTER TABLE public.repair_jobs ADD COLUMN IF NOT EXISTS service_area public.service_area_enum;
