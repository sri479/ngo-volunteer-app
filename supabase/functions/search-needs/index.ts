import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3"

const jinaKey = Deno.env.get("JINA_API_KEY")

const supabaseAdmin = createClient(
  Deno.env.get("SUPABASE_URL") ?? "",
  Deno.env.get("SERVICE_SECRET_KEY") ?? Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""
)

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Content-Type": "application/json",
}

Deno.serve(async (req) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS })
  }

  try {
    const { query, threshold = 0.4, count = 20 } = await req.json()

    if (!query || query.trim().length < 2) {
      return new Response(JSON.stringify([]), { headers: CORS_HEADERS })
    }

    console.log(`[search-needs] New search: "${query}" | threshold: ${threshold}`)

    // ─────────────────────────────────────────────────────────────
    // STEP 1: Get Embeddings from Jina AI
    // ─────────────────────────────────────────────────────────────
    if (!jinaKey) {
      throw new Error("JINA_API_KEY environment variable is not set")
    }

    const embedRes = await fetch("https://api.jina.ai/v1/embeddings", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${jinaKey}`,
      },
      body: JSON.stringify({
        model: "jina-embeddings-v2-base-en",
        task: "retrieval.query",
        input: `Find NGO field reports and community needs related to: \${query.trim()}`,
      }),
    })

    if (!embedRes.ok) {
      const errorText = await embedRes.text()
      throw new Error(`Jina AI failed with status ${embedRes.status}: ${errorText}`)
    }

    const embedData = await embedRes.json()
    const embedding = embedData.data?.[0]?.embedding
    if (!embedding) {
      throw new Error("Jina AI returned no embedding data")
    }

    // ─────────────────────────────────────────────────────────────
    // STEP 2: Semantic Search via Database RPC
    // ─────────────────────────────────────────────────────────────
    console.log(`[search-needs] Calling match_reports RPC...`)
    const { data: rpcData, error: rpcErr } = await supabaseAdmin.rpc("match_reports", {
      query_embedding: embedding,
      match_threshold: threshold,
      match_count: count,
    })

    if (rpcErr) {
      console.error(`[search-needs] RPC Error:`, rpcErr)
      throw new Error(`Database search failed: ${rpcErr.message}`)
    }

    if (!rpcData || rpcData.length === 0) {
      console.log(`[search-needs] No semantic matches found.`)
      return new Response(JSON.stringify([]), { headers: CORS_HEADERS })
    }

    // ─────────────────────────────────────────────────────────────
    // STEP 3: Enrich with full details and sorting
    // ─────────────────────────────────────────────────────────────
    const needIds = rpcData.map((r: any) => r.id)
    console.log(`[search-needs] Found ${needIds.length} candidate IDs. Fetching details...`)

    const { data: fullNeeds, error: needsErr } = await supabaseAdmin
      .from("verified_needs")
      .select(
        "id, category, priority_score, ai_summary, required_skills, status, report_id, field_reports!inner(created_at)"
      )
      .in("id", needIds)

    if (needsErr) {
      console.error(`[search-needs] Detail fetching error:`, needsErr)
      throw new Error(`Failed to enrich search results: ${needsErr.message}`)
    }

    // Map similarity back and sort by priority then similarity
    const simMap = new Map(rpcData.map((r: any) => [r.id, r.similarity]))
    const enriched = (fullNeeds ?? [])
      .map((n: any) => ({
        ...n,
        similarity: simMap.get(n.id) ?? 0
      }))
      .sort((a, b) => {
        // Sort by similarity first!
        const simDiff = b.similarity - a.similarity
        if (Math.abs(simDiff) > 0.01) { // 1% threshold to distinguish real differences
          return simDiff;
        }
        // Fallback to priority if similarity is essentially identical
        return b.priority_score - a.priority_score
      })

    console.log(`[search-needs] Search complete. Returning ${enriched.length} results.`)

    return new Response(JSON.stringify(enriched), {
      status: 200,
      headers: CORS_HEADERS,
    })

  } catch (err: any) {
    const message = err instanceof Error ? err.message : String(err)
    console.error(`[search-needs] Fatal error:`, message)

    return new Response(
      JSON.stringify({
        error: "Internal Server Error during search",
        message: message
      }),
      {
        status: 500,
        headers: CORS_HEADERS,
      }
    )
  }
})
