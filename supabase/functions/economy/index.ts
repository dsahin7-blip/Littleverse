import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json; charset=utf-8",
};

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return new Response(JSON.stringify({ error: "METHOD_NOT_ALLOWED" }), { status: 405, headers: cors });

  const authorization = req.headers.get("Authorization");
  const projectUrl = Deno.env.get("SUPABASE_URL");
  const publishableKey = req.headers.get("apikey") ?? Deno.env.get("SUPABASE_ANON_KEY") ?? Deno.env.get("SUPABASE_PUBLISHABLE_KEY");
  if (!authorization?.startsWith("Bearer ") || !projectUrl || !publishableKey) {
    return new Response(JSON.stringify({ error: "AUTH_REQUIRED" }), { status: 401, headers: cors });
  }

  let body: { action?: string; payload?: Record<string, unknown> };
  try { body = await req.json(); } catch { return new Response(JSON.stringify({ error: "INVALID_JSON" }), { status: 400, headers: cors }); }
  const actions = new Set(["initialize", "snapshot", "history", "purchase", "reward", "claim", "event", "equip", "gift"]);
  if (!body.action || !actions.has(body.action)) return new Response(JSON.stringify({ error: "INVALID_ACTION" }), { status: 400, headers: cors });

  try {
    const endpoint = body.action === "gift"
      ? `${projectUrl}/rest/v1/rpc/littleverse_npc_gift`
      : `${projectUrl}/rest/v1/rpc/littleverse_economy`;
    const rpcBody = body.action === "gift"
      ? { p_npc_id: body.payload?.npc_id, p_item_id: body.payload?.item_id }
      : { p_action: body.action, p_payload: body.payload ?? {} };
    const response = await fetch(endpoint, {
      method: "POST",
      headers: { apikey: publishableKey, Authorization: authorization, "Content-Type": "application/json" },
      body: JSON.stringify(rpcBody),
    });
    const text = await response.text();
    let result: unknown;
    try { result = JSON.parse(text); } catch { result = { error: "ECONOMY_UNAVAILABLE" }; }
    return new Response(JSON.stringify(result), { status: response.status, headers: cors });
  } catch {
    return new Response(JSON.stringify({ error: "ECONOMY_UNAVAILABLE" }), { status: 503, headers: cors });
  }
});

