import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3"

const supabaseAdmin = createClient(
  Deno.env.get("SUPABASE_URL") ?? "",
  Deno.env.get("SERVICE_SECRET_KEY") ?? Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""
)

const PRIORITY_RUBRIC = `
Score Priority using ONLY this rubric. Do not give everything a 10.
9–10 → Life-threatening RIGHT NOW: unconscious persons, active fire/chemical spill, severe injury, blocked emergency routes.
7–8  → Urgent but not immediately fatal: no clean water 24+ hrs, medical need within hours, shelter collapse risk, 50+ without food.
5–6  → Serious community need: moderate shortage, damaged but usable infrastructure, medical need within days, 10–50 affected.
3–4  → Manageable: small group (<10) needing non-critical supplies, minor damage, coordination gaps.
1–2  → Low urgency: situation improving, single person, minor inconvenience.`

const SKILLS_CATALOGUE = `
Pick RequiredSkills ONLY from this list (exact strings, 1–4 max):
"first_aid","medical","search_and_rescue","firefighting","hazmat",
"engineering","construction","logistics","food_distribution",
"water_sanitation","counseling","translation","communication","driving","coordination"`

const JSON_SCHEMA = `
Return a JSON ARRAY (even if only one issue found). Each element:
{
  "Category": "<Medical|Food|Water|Shelter|Infrastructure|Chemical|Fire|Flood|Search & Rescue|Coordination|Other>",
  "Priority": <integer 1–10>,
  "Summary": "<2–3 sentences: what happened, who is affected, what is needed>",
  "RequiredSkills": ["<skill>"]
}
If the report has 3 distinct issues, return 3 objects. No markdown, no extra text.`

// ── Detect MIME type from URL extension ──────────────────
function getMimeType(url: string): string {
  const ext = url.split("?")[0].split(".").pop()?.toLowerCase()
  const map: Record<string, string> = {
    jpg: "image/jpeg", jpeg: "image/jpeg",
    png: "image/png", webp: "image/webp",
    pdf: "application/pdf"
  }
  return map[ext ?? ""] ?? "image/jpeg"
}

// ── Download file and base64-encode it ───────────────────
async function fetchAsBase64(url: string): Promise<{ data: string; mimeType: string }> {
  const res = await fetch(url)
  if (!res.ok) throw new Error(`Failed to fetch file: ${res.status} ${res.statusText}`)
  const buffer = await res.arrayBuffer()
  const bytes = new Uint8Array(buffer)
  let binary = ""
  for (const b of bytes) binary += String.fromCharCode(b)
  return {
    data: btoa(binary),
    mimeType: getMimeType(url)
  }
}

serve(async (req) => {
  try {
    const geminiKey = Deno.env.get("GEMINI_API_KEY")
    const jinaKey = Deno.env.get("JINA_API_KEY")
    if (!geminiKey) throw new Error("GEMINI_API_KEY is not set")
    if (!jinaKey) throw new Error("JINA_API_KEY is not set")

    const payload = await req.json()
    const record = payload.record
    if (!record?.id) throw new Error("No record found in payload")

    const hasImage = !!record.image_url
    console.log(`[1] Analyzing report ${record.id} | mode: ${hasImage ? "vision (image/PDF)" : "text"}`)

    // ─────────────────────────────────────────────────────
    // STEP 1: Build Gemini request
    // Text-only → use raw_description
    // Has image → download file, send to Gemini Vision
    // Has both  → send both (surveyor typed notes + scanned paper)
    // ─────────────────────────────────────────────────────
    const promptText = `You are an AI for an NGO disaster response system.
Analyze the field report below. A single report may contain MULTIPLE distinct issues — extract ALL of them as separate objects.

${PRIORITY_RUBRIC}
${SKILLS_CATALOGUE}
${JSON_SCHEMA}

${record.raw_description ? `Surveyor notes: "${record.raw_description}"` : ""}
${hasImage ? "(A scanned document or photo is also attached — extract issues from it too.)" : ""}`

    // Build the parts array for Gemini
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const parts: any[] = [{ text: promptText }]

    if (hasImage) {
      const { data, mimeType } = await fetchAsBase64(record.image_url)
      parts.push({ inline_data: { mime_type: mimeType, data } })
    }

    const extractResponse = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=${geminiKey}`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ contents: [{ parts }] })
      }
    )

    const aiData = await extractResponse.json()
    if (aiData.error) throw new Error(`Gemini Error: ${aiData.error.message}`)

    let rawText = aiData.candidates[0].content.parts[0].text
    rawText = rawText.replace(/```json|```/g, "").trim()

    let issues: Array<{
      Category: string
      Priority: number
      Summary: string
      RequiredSkills: string[]
    }>

    try {
      const parsed = JSON.parse(rawText)
      // Handle both array response and accidental single-object response
      issues = Array.isArray(parsed) ? parsed : [parsed]
    } catch {
      throw new Error(`Failed to parse Gemini JSON. Raw output: ${rawText}`)
    }

    console.log(`[1] Extracted ${issues.length} issue(s)`)

    // ─────────────────────────────────────────────────────
    // STEP 2 + 3: For each issue → embed → insert
    // ─────────────────────────────────────────────────────
    for (let i = 0; i < issues.length; i++) {
      const issue = issues[i]

      const category = issue.Category ?? "Other"
      const priority = issue.Priority ?? 5
      const summary = issue.Summary
      const requiredSkills = issue.RequiredSkills ?? []

      if (!summary) {
        console.warn(`[!] Issue ${i + 1} has no summary, skipping`)
        continue
      }

      console.log(`[2.${i + 1}] Embedding: "${category}" | Priority ${priority}`)

      // Embed category + summary for richer semantic search
      const embedResponse = await fetch("https://api.jina.ai/v1/embeddings", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Authorization": `Bearer ${jinaKey}`
        },
        body: JSON.stringify({
          model: "jina-embeddings-v2-base-en",
          input: `${category}: ${summary}`
        })
      })

      const embedData = await embedResponse.json()
      if (embedData.error) throw new Error(`Jina Error: ${JSON.stringify(embedData.error)}`)

      const embeddingVec = embedData.data?.[0]?.embedding
      if (!embeddingVec) throw new Error(`No embedding returned for issue ${i + 1}`)

      // Insert one row per issue
      const { error: insertError } = await supabaseAdmin
        .from("verified_needs")
        .insert({
          report_id: record.id,
          category: category,
          priority_score: priority,
          ai_summary: summary,
          required_skills: requiredSkills,
          embedding: embeddingVec
        })

      if (insertError) throw insertError

      console.log(`[3.${i + 1}] Saved issue ${i + 1}/${issues.length}`)
    }

    // ─────────────────────────────────────────────────────
    // STEP 4: Mark original report as processed
    // ─────────────────────────────────────────────────────
    await supabaseAdmin
      .from("field_reports")
      .update({ is_processed: true })
      .eq("id", record.id)

    console.log(`[✓] Done — ${issues.length} verified need(s) created from report ${record.id}`)
    return new Response(
      JSON.stringify({ success: true, issues_extracted: issues.length }),
      { status: 200 }
    )

  } catch (err) {
    console.error("[✗] Error:", err.message)
    return new Response(JSON.stringify({ error: err.message }), { status: 500 })
  }
})