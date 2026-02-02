#!/bin/bash
# ============================================
# COMANDOS RÁPIDOS DE SETUP
# Copia y pega estos comandos en tu terminal
# ============================================

# 1. Instalar Supabase CLI (si no lo tienes)
npm install -g supabase

# 2. Login en Supabase
supabase login

# 3. Ir al directorio del proyecto
cd trading-bot

# 4. Inicializar proyecto Supabase (si es necesario)
supabase init

# 5. Link con tu proyecto
supabase link --project-ref TU_PROJECT_REF

# 6. Configurar secrets
supabase secrets set ALPACA_KEY=TU_ALPACA_KEY
supabase secrets set ALPACA_SECRET=TU_ALPACA_SECRET
supabase secrets set OPENAI_KEY=TU_OPENAI_KEY

# 7. Deploy de la Edge Function (con --no-verify-jwt para que pg_cron pueda llamarla)
supabase functions deploy trading-agent --no-verify-jwt

# 8. Test manual
curl -X POST 'https://TU_PROJECT_REF.supabase.co/functions/v1/trading-agent' \
  -H 'Authorization: Bearer TU_SERVICE_ROLE_KEY' \
  -H 'Content-Type: application/json'
