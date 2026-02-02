-- Vista: Reporte completo del bot
CREATE OR REPLACE VIEW trading_report AS
WITH portfolio_summary AS (
    SELECT 'PORTAFOLIO' as seccion, 1 as orden,
        'Equity actual: $' || COALESCE(TO_CHAR(equity, 'FM999,999.00'), '0') as linea
    FROM portfolio_snapshots ORDER BY created_at DESC LIMIT 1
),
portfolio_initial AS (
    SELECT 'PORTAFOLIO' as seccion, 2 as orden,
        'Equity inicial: $' || COALESCE(TO_CHAR(equity, 'FM999,999.00'), '0') as linea
    FROM portfolio_snapshots ORDER BY created_at ASC LIMIT 1
),
portfolio_return AS (
    SELECT 'PORTAFOLIO' as seccion, 3 as orden,
        'Rendimiento: ' || COALESCE(
            TO_CHAR(
                ((SELECT equity FROM portfolio_snapshots ORDER BY created_at DESC LIMIT 1) -
                 (SELECT equity FROM portfolio_snapshots ORDER BY created_at ASC LIMIT 1)) /
                NULLIF((SELECT equity FROM portfolio_snapshots ORDER BY created_at ASC LIMIT 1), 0) * 100,
                'FM990.00') || '%', 'N/A') as linea
),
portfolio_cash AS (
    SELECT 'PORTAFOLIO' as seccion, 4 as orden,
        'Cash disponible: $' || COALESCE(TO_CHAR(buying_power, 'FM999,999.00'), '0') as linea
    FROM portfolio_snapshots ORDER BY created_at DESC LIMIT 1
),
positions_header AS (
    SELECT 'POSICIONES' as seccion, 10 as orden, '---' as linea
),
positions_data AS (
    SELECT 'POSICIONES' as seccion,
        11 + ROW_NUMBER() OVER (ORDER BY created_at DESC) as orden,
        (pos->>'symbol') || ': ' || (pos->>'qty') || ' acciones @ $' ||
        TO_CHAR((pos->>'current_price')::numeric, 'FM999,999.00') ||
        ' (P/L: ' || TO_CHAR((pos->>'unrealized_plpc')::numeric * 100, 'FM990.00') || '%)' as linea
    FROM portfolio_snapshots ps, LATERAL jsonb_array_elements(positions) as pos
    WHERE ps.created_at = (SELECT MAX(created_at) FROM portfolio_snapshots)
    AND jsonb_array_length(positions) > 0
),
positions_empty AS (
    SELECT 'POSICIONES' as seccion, 12 as orden, '(Sin posiciones abiertas)' as linea
    WHERE NOT EXISTS (
        SELECT 1 FROM portfolio_snapshots
        WHERE created_at = (SELECT MAX(created_at) FROM portfolio_snapshots)
        AND jsonb_array_length(positions) > 0
    )
),
moves_header AS (
    SELECT 'MOVIMIENTOS' as seccion, 20 as orden, '---' as linea
),
moves_data AS (
    SELECT 'MOVIMIENTOS' as seccion,
        20 + ROW_NUMBER() OVER (ORDER BY created_at DESC) as orden,
        TO_CHAR(created_at, 'DD/MM HH24:MI') || ' | ' || action || ' ' ||
        COALESCE(symbol, '') || ' ' || COALESCE(quantity::text, '') ||
        ' | ' || LEFT(reasoning, 50) as linea
    FROM trading_decisions ORDER BY created_at DESC LIMIT 5
),
orders_header AS (
    SELECT 'ORDENES' as seccion, 30 as orden, '---' as linea
),
orders_data AS (
    SELECT 'ORDENES' as seccion,
        30 + ROW_NUMBER() OVER (ORDER BY created_at DESC) as orden,
        CASE
            WHEN status IN ('filled', 'partially_filled') THEN '[OK] '
            WHEN status IN ('accepted', 'pending_new', 'new') THEN '[PEND] '
            ELSE '[X] '
        END ||
        TO_CHAR(created_at, 'DD/MM HH24:MI') || ' | ' ||
        UPPER(side) || ' ' || symbol || ' x' || qty ||
        CASE WHEN filled_avg_price IS NOT NULL
            THEN ' @ $' || TO_CHAR(filled_avg_price, 'FM999,999.00') ELSE '' END ||
        ' [' || status || ']' as linea
    FROM executed_orders ORDER BY created_at DESC LIMIT 10
)
SELECT seccion, orden, linea FROM portfolio_summary
UNION ALL SELECT * FROM portfolio_initial
UNION ALL SELECT * FROM portfolio_return
UNION ALL SELECT * FROM portfolio_cash
UNION ALL SELECT * FROM positions_header
UNION ALL SELECT * FROM positions_data
UNION ALL SELECT * FROM positions_empty
UNION ALL SELECT * FROM moves_header
UNION ALL SELECT * FROM moves_data
UNION ALL SELECT * FROM orders_header
UNION ALL SELECT * FROM orders_data
ORDER BY orden;

-- Función simple para ver reporte
CREATE OR REPLACE FUNCTION reporte()
RETURNS TABLE(info TEXT) AS $$
BEGIN
    RETURN QUERY
    SELECT CASE
        WHEN seccion != LAG(seccion) OVER (ORDER BY orden) OR LAG(seccion) OVER (ORDER BY orden) IS NULL
        THEN E'\n=== ' || seccion || ' ===\n' || linea
        ELSE linea
    END as info
    FROM trading_report ORDER BY orden;
END;
$$ LANGUAGE plpgsql;
