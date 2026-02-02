// ============================================
// TRADING AGENT - Supabase Edge Function
// File: supabase/functions/trading-agent/index.ts
// ============================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// Configuración
const ALPACA_BASE_URL = "https://paper-api.alpaca.markets";
const ALPACA_DATA_URL = "https://data.alpaca.markets";

// Interfaces
interface Position {
  symbol: string;
  qty: string;
  market_value: string;
  unrealized_pl: string;
  unrealized_plpc: string;
  current_price: string;
}

interface Account {
  equity: string;
  buying_power: string;
  cash: string;
  portfolio_value: string;
}

interface TradingDecision {
  action: "BUY" | "SELL" | "HOLD";
  symbol: string;
  quantity: number;
  reasoning: string;
}

// Helper: Alpaca API calls
async function alpacaRequest(
  endpoint: string,
  method: string = "GET",
  body?: object
) {
  const ALPACA_KEY = Deno.env.get("ALPACA_KEY")!;
  const ALPACA_SECRET = Deno.env.get("ALPACA_SECRET")!;

  const url = endpoint.startsWith("/v2/stocks")
    ? `${ALPACA_DATA_URL}${endpoint}`
    : `${ALPACA_BASE_URL}${endpoint}`;

  const response = await fetch(url, {
    method,
    headers: {
      "APCA-API-KEY-ID": ALPACA_KEY,
      "APCA-API-SECRET-KEY": ALPACA_SECRET,
      "Content-Type": "application/json",
    },
    body: body ? JSON.stringify(body) : undefined,
  });

  if (!response.ok) {
    const error = await response.text();
    throw new Error(`Alpaca API error: ${response.status} - ${error}`);
  }

  return response.json();
}

// Get account info
async function getAccount(): Promise<Account> {
  return alpacaRequest("/v2/account");
}

// Get current positions
async function getPositions(): Promise<Position[]> {
  return alpacaRequest("/v2/positions");
}

// Get stock universe from DB
async function getStockUniverse(supabase: any): Promise<string[]> {
  const { data, error } = await supabase
    .from("stock_universe")
    .select("symbol")
    .eq("is_active", true);

  if (error) throw error;
  return data.map((row: any) => row.symbol);
}

// Get latest quotes for symbols
async function getQuotes(symbols: string[]): Promise<Record<string, any>> {
  const symbolsParam = symbols.join(",");
  return alpacaRequest(`/v2/stocks/quotes/latest?symbols=${symbolsParam}`);
}

// Submit order to Alpaca
async function submitOrder(
  symbol: string,
  qty: number,
  side: "buy" | "sell"
): Promise<any> {
  return alpacaRequest("/v2/orders", "POST", {
    symbol,
    qty: qty.toString(),
    side,
    type: "market",
    time_in_force: "day",
  });
}

// Ask GPT for trading decision
async function askGPT(
  account: Account,
  positions: Position[],
  quotes: Record<string, any>,
  universe: string[]
): Promise<{ analysis: string; decision: TradingDecision }> {
  const OPENAI_KEY = Deno.env.get("OPENAI_KEY")!;

  const positionsText = positions.length > 0
    ? positions.map(p => 
        `- ${p.symbol}: ${p.qty} shares @ $${parseFloat(p.current_price).toFixed(2)} (P/L: ${parseFloat(p.unrealized_plpc).toFixed(2)}%)`
      ).join("\n")
    : "No positions currently held.";

  const quotesText = Object.entries(quotes.quotes || {})
    .map(([symbol, q]: [string, any]) => 
      `- ${symbol}: Bid $${q.bp?.toFixed(2) || 'N/A'} / Ask $${q.ap?.toFixed(2) || 'N/A'}`
    ).join("\n");

  const prompt = `You are an AI trading agent managing a paper trading portfolio. Your goal is to maximize returns while managing risk.

CURRENT PORTFOLIO STATUS:
- Equity: $${parseFloat(account.equity).toFixed(2)}
- Buying Power: $${parseFloat(account.buying_power).toFixed(2)}
- Cash: $${parseFloat(account.cash).toFixed(2)}

CURRENT POSITIONS:
${positionsText}

AVAILABLE STOCKS TO TRADE:
${universe.join(", ")}

CURRENT MARKET QUOTES:
${quotesText}

RULES:
1. You can only trade stocks from the available list
2. Maximum position size: 20% of portfolio per stock
3. Keep at least 20% in cash for opportunities
4. Consider both momentum and mean-reversion strategies
5. Avoid overtrading - only trade if there's a clear opportunity

Based on the current market conditions and portfolio, decide your next action.

Respond in this exact JSON format:
{
  "analysis": "Your brief market analysis and reasoning (2-3 sentences)",
  "decision": {
    "action": "BUY" or "SELL" or "HOLD",
    "symbol": "TICKER" (required if BUY/SELL, use "" if HOLD),
    "quantity": number (required if BUY/SELL, use 0 if HOLD),
    "reasoning": "One sentence explanation of the decision"
  }
}`;

  const response = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${OPENAI_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: "gpt-5-mini",
      messages: [
        {
          role: "system",
          content: "You are a quantitative trading agent. Always respond with valid JSON only, no markdown or extra text."
        },
        { role: "user", content: prompt }
      ],
      max_completion_tokens: 2000,
    }),
  });

  if (!response.ok) {
    const error = await response.text();
    throw new Error(`OpenAI API error: ${response.status} - ${error}`);
  }

  const data = await response.json();
  const content = data.choices[0].message.content;

  try {
    // Clean potential markdown code blocks
    const cleaned = content.replace(/```json\n?|\n?```/g, "").trim();
    return JSON.parse(cleaned);
  } catch (e) {
    console.error("Failed to parse GPT response:", content);
    throw new Error(`Failed to parse GPT response: ${e}`);
  }
}

// Save decision to database
async function saveDecision(
  supabase: any,
  account: Account,
  positions: Position[],
  analysis: string,
  decision: TradingDecision,
  orderResult: any,
  executionTime: number
) {
  const { data, error } = await supabase
    .from("trading_decisions")
    .insert({
      portfolio_value: parseFloat(account.portfolio_value),
      buying_power: parseFloat(account.buying_power),
      positions: positions,
      market_analysis: analysis,
      action: decision.action,
      symbol: decision.symbol || null,
      quantity: decision.quantity || null,
      reasoning: decision.reasoning,
      order_id: orderResult?.id || null,
      order_status: orderResult?.status || null,
      order_error: orderResult?.error || null,
      execution_time_ms: executionTime,
    })
    .select()
    .single();

  if (error) throw error;
  return data;
}

// Save portfolio snapshot
async function saveSnapshot(
  supabase: any,
  account: Account,
  positions: Position[]
) {
  // Get previous snapshot for comparison
  const { data: prevSnapshot } = await supabase
    .from("portfolio_snapshots")
    .select("equity")
    .order("created_at", { ascending: false })
    .limit(1)
    .single();

  const currentEquity = parseFloat(account.equity);
  const prevEquity = prevSnapshot?.equity || currentEquity;
  const equityChange = currentEquity - prevEquity;
  const equityChangePct = prevEquity > 0 ? (equityChange / prevEquity) * 100 : 0;

  const { error } = await supabase.from("portfolio_snapshots").insert({
    equity: currentEquity,
    buying_power: parseFloat(account.buying_power),
    cash: parseFloat(account.cash),
    portfolio_value: parseFloat(account.portfolio_value),
    equity_change: equityChange,
    equity_change_pct: equityChangePct,
    positions: positions,
  });

  if (error) throw error;
}

// Save executed order
async function saveOrder(
  supabase: any,
  order: any,
  decisionId: number
) {
  const { error } = await supabase.from("executed_orders").insert({
    alpaca_order_id: order.id,
    symbol: order.symbol,
    side: order.side,
    qty: parseInt(order.qty),
    type: order.type,
    status: order.status,
    filled_avg_price: order.filled_avg_price ? parseFloat(order.filled_avg_price) : null,
    filled_qty: order.filled_qty ? parseInt(order.filled_qty) : null,
    decision_id: decisionId,
  });

  if (error) throw error;
}

// Main handler
Deno.serve(async (req) => {
  const startTime = Date.now();

  try {
    // Initialize Supabase client
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    console.log("🤖 Trading agent starting...");

    // 1. Get current portfolio state
    const [account, positions, universe] = await Promise.all([
      getAccount(),
      getPositions(),
      getStockUniverse(supabase),
    ]);

    console.log(`📊 Portfolio: $${parseFloat(account.equity).toFixed(2)}`);
    console.log(`📈 Positions: ${positions.length}`);

    // 2. Get market quotes
    const quotes = await getQuotes(universe);

    // 3. Ask GPT for decision
    console.log("🧠 Asking GPT for trading decision...");
    const { analysis, decision } = await askGPT(account, positions, quotes, universe);

    console.log(`💡 Decision: ${decision.action} ${decision.symbol || ""} ${decision.quantity || ""}`);

    // 4. Execute order if not HOLD
    let orderResult: any = null;
    if (decision.action !== "HOLD" && decision.symbol && decision.quantity > 0) {
      try {
        const side = decision.action.toLowerCase() as "buy" | "sell";
        orderResult = await submitOrder(decision.symbol, decision.quantity, side);
        console.log(`✅ Order submitted: ${orderResult.id}`);
      } catch (e: any) {
        console.error(`❌ Order failed: ${e.message}`);
        orderResult = { error: e.message };
      }
    }

    const executionTime = Date.now() - startTime;

    // 5. Save everything to database
    const savedDecision = await saveDecision(
      supabase,
      account,
      positions,
      analysis,
      decision,
      orderResult,
      executionTime
    );

    await saveSnapshot(supabase, account, positions);

    if (orderResult?.id) {
      await saveOrder(supabase, orderResult, savedDecision.id);
    }

    console.log(`⏱️ Completed in ${executionTime}ms`);

    return new Response(
      JSON.stringify({
        success: true,
        decision: decision,
        analysis: analysis,
        order: orderResult,
        execution_time_ms: executionTime,
      }),
      {
        headers: { "Content-Type": "application/json" },
        status: 200,
      }
    );
  } catch (error: any) {
    console.error("❌ Error:", error.message);

    return new Response(
      JSON.stringify({
        success: false,
        error: error.message,
      }),
      {
        headers: { "Content-Type": "application/json" },
        status: 500,
      }
    );
  }
});
