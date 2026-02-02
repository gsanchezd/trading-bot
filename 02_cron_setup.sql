-- ============================================
-- PG_CRON SETUP
-- Ejecutar en Supabase SQL Editor DESPUÉS de deployar la Edge Function
-- ============================================

-- Primero, guarda la URL de tu proyecto y el service key en Vault
-- (Esto es más seguro que hardcodear)

-- Insertar secrets en Vault (reemplaza con tus valores reales)
-- NOTA: Ejecuta esto UNA SOLA VEZ

INSERT INTO vault.secrets (name, secret)
VALUES
    ('project_url', 'https://TU_PROJECT_REF.supabase.co'),
    ('service_role_key', 'TU_SERVICE_ROLE_KEY')
ON CONFLICT (name) DO UPDATE SET secret = EXCLUDED.secret;

-- Habilitar la extensión pg_cron (si no está habilitada)
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- Habilitar pg_net para hacer HTTP requests
CREATE EXTENSION IF NOT EXISTS pg_net;

-- Crear el cron job que ejecuta cada hora
-- El schedule '0 * * * *' significa "minuto 0 de cada hora"
SELECT cron.schedule(
    'trading-agent-hourly',  -- nombre del job
    '0 * * * *',             -- cada hora en punto
    $$
    SELECT net.http_post(
        url := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'project_url') 
               || '/functions/v1/trading-agent',
        headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key')
        ),
        body := '{}'::jsonb
    );
    $$
);

-- ============================================
-- COMANDOS ÚTILES
-- ============================================

-- Ver todos los cron jobs activos:
-- SELECT * FROM cron.job;

-- Ver historial de ejecuciones:
-- SELECT * FROM cron.job_run_details ORDER BY start_time DESC LIMIT 20;

-- Desactivar el job temporalmente:
-- SELECT cron.unschedule('trading-agent-hourly');

-- Reactivar el job:
-- (ejecutar de nuevo el SELECT cron.schedule de arriba)

-- Ejecutar manualmente (para testing):
-- SELECT net.http_post(
--     url := 'https://TU_PROJECT_REF.supabase.co/functions/v1/trading-agent',
--     headers := '{"Content-Type": "application/json", "Authorization": "Bearer TU_SERVICE_ROLE_KEY"}'::jsonb,
--     body := '{}'::jsonb
-- );
