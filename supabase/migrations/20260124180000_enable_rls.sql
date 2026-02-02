-- Activar RLS en todas las tablas del trading bot
-- Solo service_role (Edge Function) podrá acceder

ALTER TABLE trading_decisions ENABLE ROW LEVEL SECURITY;
ALTER TABLE portfolio_snapshots ENABLE ROW LEVEL SECURITY;
ALTER TABLE executed_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE stock_universe ENABLE ROW LEVEL SECURITY;
