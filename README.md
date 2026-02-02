# Trading Bot Autónomo

Bot de trading que usa GPT-5-mini para tomar decisiones cada hora, ejecuta en Alpaca Paper Trading, y guarda todo en Supabase.

## Arquitectura

```
┌─────────────────────────────────────────────────────────┐
│                      SUPABASE                           │
│  ┌──────────┐    ┌──────────────┐    ┌──────────────┐  │
│  │ pg_cron  │───▶│ Edge Function │───▶│  PostgreSQL  │  │
│  │ (1 hora) │    │ trading-agent │    │   (logs)     │  │
│  └──────────┘    └──────┬───────┘    └──────────────┘  │
└─────────────────────────┼───────────────────────────────┘
                          │
              ┌───────────┴───────────┐
              ▼                       ▼
      ┌──────────────┐       ┌──────────────┐
      │   OpenAI     │       │   Alpaca     │
      │  GPT-5-mini  │       │ Paper Trading│
      └──────────────┘       └──────────────┘
```

---

## Requisitos Previos

Necesitas cuentas en:

| Servicio | URL | Qué obtener |
|----------|-----|-------------|
| **Supabase** | https://supabase.com | Project URL, Project Ref, Service Role Key |
| **Alpaca** | https://alpaca.markets | API Key y Secret (Paper Trading) |
| **OpenAI** | https://platform.openai.com | API Key |

---

## Configuración Paso a Paso

### Paso 1: Obtener las Credenciales

#### 1.1 Supabase
1. Crea un proyecto en https://supabase.com/dashboard
2. Ve a **Settings** → **API**
3. Anota:
   - **Project URL**: `https://xxxxxx.supabase.co`
   - **Project Reference**: el `xxxxxx` de tu URL
   - **Service Role Key**: bajo "Project API Keys" (la key `service_role`, NO la `anon`)

#### 1.2 Alpaca (Paper Trading)
1. Crea cuenta en https://alpaca.markets
2. Ve a https://app.alpaca.markets/paper/dashboard/overview
3. Click en **View API Keys**
4. Anota:
   - **API Key ID**: `PK...`
   - **Secret Key**: se muestra una sola vez

#### 1.3 OpenAI
1. Ve a https://platform.openai.com/api-keys
2. Crea una nueva API Key
3. Anota la key: `sk-proj-...`

---

### Paso 2: Crear las Tablas en Supabase

1. Ve a tu proyecto en Supabase Dashboard
2. Click en **SQL Editor**
3. Copia todo el contenido de `01_schema.sql`
4. Click **Run**

Esto crea las tablas:
- `trading_decisions` - Cada decisión del agente
- `portfolio_snapshots` - Estado del portafolio cada hora
- `executed_orders` - Órdenes ejecutadas
- `stock_universe` - Acciones que el bot puede tradear

**Seguridad:** El script también habilita Row Level Security (RLS) en todas las tablas. Esto significa que:
- La API pública (`anon` key) **no puede** leer ni escribir datos
- Solo el `service_role` (usado por Edge Functions) tiene acceso
- Tus datos de trading están protegidos de acceso no autorizado

---

### Paso 3: Configurar y Deployar la Edge Function

#### 3.1 Instalar Supabase CLI

```bash
npm install -g supabase
```

#### 3.2 Login y Link

```bash
supabase login
supabase link --project-ref TU_PROJECT_REF
```

**Cambiar:** `TU_PROJECT_REF` → tu Project Reference de Supabase (ej: `abcd1234xyz`)

#### 3.3 Configurar Secrets

```bash
supabase secrets set ALPACA_KEY=TU_ALPACA_KEY
supabase secrets set ALPACA_SECRET=TU_ALPACA_SECRET
supabase secrets set OPENAI_KEY=TU_OPENAI_KEY
```

**Cambiar:**
- `TU_ALPACA_KEY` → tu API Key de Alpaca (ej: `PKXXXXXXXXXXXXXXXX`)
- `TU_ALPACA_SECRET` → tu Secret de Alpaca
- `TU_OPENAI_KEY` → tu API Key de OpenAI (ej: `sk-proj-xxx...`)

#### 3.4 Deploy

```bash
supabase functions deploy trading-agent --no-verify-jwt
```

---

### Paso 4: Configurar el Cron Job

1. Ve a **SQL Editor** en Supabase
2. Abre el archivo `02_cron_setup.sql`
3. **Edita las líneas 13-16** con tus valores:

```sql
INSERT INTO vault.secrets (name, secret)
VALUES
    ('project_url', 'https://TU_PROJECT_REF.supabase.co'),
    ('service_role_key', 'TU_SERVICE_ROLE_KEY')
```

**Cambiar:**
- `TU_PROJECT_REF` → tu Project Reference
- `TU_SERVICE_ROLE_KEY` → tu Service Role Key de Supabase

4. Click **Run**

---

### Paso 5: Verificar que Funciona

#### Test Manual

```bash
curl -X POST 'https://TU_PROJECT_REF.supabase.co/functions/v1/trading-agent' \
  -H 'Authorization: Bearer TU_SERVICE_ROLE_KEY' \
  -H 'Content-Type: application/json'
```

**Cambiar:**
- `TU_PROJECT_REF` → tu Project Reference
- `TU_SERVICE_ROLE_KEY` → tu Service Role Key

#### Ver Logs

En Supabase Dashboard: **Edge Functions** → **trading-agent** → **Logs**

#### Ver Decisiones

```sql
SELECT * FROM trading_decisions ORDER BY created_at DESC LIMIT 10;
```

---

## Resumen de Archivos a Modificar

| Archivo | Qué cambiar | Líneas |
|---------|-------------|--------|
| `02_cron_setup.sql` | `project_url` y `service_role_key` | 14-15 |

Los demás valores se configuran via CLI con `supabase secrets set`.

---

## Resumen de Placeholders

| Placeholder | Dónde obtenerlo | Ejemplo |
|-------------|-----------------|---------|
| `TU_PROJECT_REF` | Supabase → Settings → General | `abcd1234xyz` |
| `TU_SERVICE_ROLE_KEY` | Supabase → Settings → API | `eyJhbGciOiJIUzI1...` |
| `TU_ALPACA_KEY` | Alpaca → Paper → API Keys | `PKXXXXXXXXXXXXXXXX` |
| `TU_ALPACA_SECRET` | Alpaca → Paper → API Keys | `xxxxxxxxxxxxxxxxxxxxxxxx` |
| `TU_OPENAI_KEY` | OpenAI → API Keys | `sk-proj-xxx...` |

---

## Monitoreo

### Ver últimas decisiones
```sql
SELECT
    created_at,
    action,
    symbol,
    quantity,
    reasoning,
    portfolio_value
FROM trading_decisions
ORDER BY created_at DESC
LIMIT 20;
```

### Ver evolución del portafolio
```sql
SELECT
    DATE(created_at) as fecha,
    MAX(equity) as max_equity,
    MIN(equity) as min_equity,
    AVG(equity_change_pct) as avg_change_pct
FROM portfolio_snapshots
GROUP BY DATE(created_at)
ORDER BY fecha DESC;
```

### Ver rendimiento total
```sql
SELECT * FROM get_total_return();
```

---

## Comandos Útiles

```bash
# Ver logs en tiempo real
supabase functions logs trading-agent

# Pausar el bot
# En SQL Editor:
SELECT cron.unschedule('trading-agent-hourly');

# Reactivar el bot
# Ejecutar de nuevo 02_cron_setup.sql
```

---

## Costos Estimados

| Servicio | Costo mensual |
|----------|---------------|
| Supabase Free | $0 |
| OpenAI GPT-5-mini (~720 calls) | ~$0.20 |
| Alpaca Paper Trading | $0 |
| **Total** | **~$0.20/mes** |

---

## Troubleshooting

| Error | Solución |
|-------|----------|
| `Edge Function timeout` | Reducir el universo de acciones en `stock_universe` |
| `Alpaca API error 403` | Verificar que usas keys de Paper Trading y que el mercado está abierto (9:30-16:00 ET) |
| `El cron no ejecuta` | Verificar en `SELECT * FROM cron.job` que existe el job |
| `OpenAI error` | Verificar que la API key es válida y tiene créditos |
