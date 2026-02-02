-- ============================================
-- TRADING BOT SCHEMA
-- Ejecutar en Supabase SQL Editor
-- ============================================

-- Tabla de decisiones del agente
CREATE TABLE IF NOT EXISTS trading_decisions (
    id BIGSERIAL PRIMARY KEY,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    
    -- Contexto del mercado
    portfolio_value DECIMAL(12,2),
    buying_power DECIMAL(12,2),
    positions JSONB,  -- posiciones actuales
    
    -- Análisis del agente
    market_analysis TEXT,  -- razonamiento de GPT
    
    -- Decisión
    action TEXT CHECK (action IN ('BUY', 'SELL', 'HOLD')),
    symbol VARCHAR(10),
    quantity INTEGER,
    reasoning TEXT,
    
    -- Resultado de la orden
    order_id VARCHAR(100),
    order_status VARCHAR(50),
    order_error TEXT,
    
    -- Métricas
    execution_time_ms INTEGER
);

-- Tabla de estado del portafolio (snapshot cada hora)
CREATE TABLE IF NOT EXISTS portfolio_snapshots (
    id BIGSERIAL PRIMARY KEY,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    
    equity DECIMAL(12,2),
    buying_power DECIMAL(12,2),
    cash DECIMAL(12,2),
    portfolio_value DECIMAL(12,2),
    
    -- Cambio desde último snapshot
    equity_change DECIMAL(12,2),
    equity_change_pct DECIMAL(8,4),
    
    -- Posiciones detalladas
    positions JSONB
);

-- Tabla de órdenes ejecutadas
CREATE TABLE IF NOT EXISTS executed_orders (
    id BIGSERIAL PRIMARY KEY,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    
    alpaca_order_id VARCHAR(100),
    symbol VARCHAR(10),
    side VARCHAR(10),  -- buy/sell
    qty INTEGER,
    type VARCHAR(20),  -- market/limit
    status VARCHAR(50),
    
    filled_avg_price DECIMAL(12,4),
    filled_qty INTEGER,
    
    decision_id BIGINT REFERENCES trading_decisions(id)
);

-- Tabla de configuración del universo de acciones
CREATE TABLE IF NOT EXISTS stock_universe (
    symbol VARCHAR(10) PRIMARY KEY,
    name VARCHAR(100),
    sector VARCHAR(50),
    added_at TIMESTAMPTZ DEFAULT NOW(),
    is_active BOOLEAN DEFAULT TRUE
);

-- Insertar universo inicial de acciones (tech + diversificado)
INSERT INTO stock_universe (symbol, name, sector) VALUES
    ('AAPL', 'Apple Inc.', 'Technology'),
    ('MSFT', 'Microsoft Corporation', 'Technology'),
    ('GOOGL', 'Alphabet Inc.', 'Technology'),
    ('AMZN', 'Amazon.com Inc.', 'Consumer Cyclical'),
    ('NVDA', 'NVIDIA Corporation', 'Technology'),
    ('META', 'Meta Platforms Inc.', 'Technology'),
    ('TSLA', 'Tesla Inc.', 'Consumer Cyclical'),
    ('JPM', 'JPMorgan Chase & Co.', 'Financial'),
    ('V', 'Visa Inc.', 'Financial'),
    ('JNJ', 'Johnson & Johnson', 'Healthcare')
ON CONFLICT (symbol) DO NOTHING;

-- Índices para consultas rápidas
CREATE INDEX IF NOT EXISTS idx_decisions_created_at ON trading_decisions(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_snapshots_created_at ON portfolio_snapshots(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_orders_symbol ON executed_orders(symbol);

-- ============================================
-- SEGURIDAD: Row Level Security (RLS)
-- ============================================
-- Habilitar RLS en todas las tablas
-- Sin políticas = solo service_role puede acceder (Edge Functions)
-- Esto bloquea acceso desde la API pública (anon key)

ALTER TABLE trading_decisions ENABLE ROW LEVEL SECURITY;
ALTER TABLE portfolio_snapshots ENABLE ROW LEVEL SECURITY;
ALTER TABLE executed_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE stock_universe ENABLE ROW LEVEL SECURITY;

-- Vista para resumen de rendimiento
CREATE OR REPLACE VIEW performance_summary AS
WITH daily_data AS (
    SELECT
        DATE(created_at) as date,
        equity,
        ROW_NUMBER() OVER (PARTITION BY DATE(created_at) ORDER BY created_at DESC) as rn
    FROM portfolio_snapshots
)
SELECT
    date,
    MIN(equity) as min_equity,
    MAX(equity) as max_equity,
    MAX(CASE WHEN rn = 1 THEN equity END) as closing_equity,
    COUNT(*) as snapshots_count
FROM daily_data
GROUP BY date
ORDER BY date DESC;

-- Función para calcular rendimiento total
CREATE OR REPLACE FUNCTION get_total_return()
RETURNS TABLE(
    initial_equity DECIMAL,
    current_equity DECIMAL,
    total_return DECIMAL,
    total_return_pct DECIMAL,
    days_active INTEGER,
    total_trades INTEGER
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        (SELECT equity FROM portfolio_snapshots ORDER BY created_at ASC LIMIT 1) as initial_equity,
        (SELECT equity FROM portfolio_snapshots ORDER BY created_at DESC LIMIT 1) as current_equity,
        (SELECT equity FROM portfolio_snapshots ORDER BY created_at DESC LIMIT 1) - 
        (SELECT equity FROM portfolio_snapshots ORDER BY created_at ASC LIMIT 1) as total_return,
        CASE 
            WHEN (SELECT equity FROM portfolio_snapshots ORDER BY created_at ASC LIMIT 1) > 0 THEN
                ((SELECT equity FROM portfolio_snapshots ORDER BY created_at DESC LIMIT 1) - 
                 (SELECT equity FROM portfolio_snapshots ORDER BY created_at ASC LIMIT 1)) / 
                (SELECT equity FROM portfolio_snapshots ORDER BY created_at ASC LIMIT 1) * 100
            ELSE 0
        END as total_return_pct,
        (SELECT EXTRACT(DAY FROM NOW() - MIN(created_at))::INTEGER FROM portfolio_snapshots) as days_active,
        (SELECT COUNT(*)::INTEGER FROM executed_orders) as total_trades;
END;
$$ LANGUAGE plpgsql;
