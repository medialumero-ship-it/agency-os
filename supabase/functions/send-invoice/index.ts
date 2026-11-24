// Agency OS — email an invoice (PDF attached) to a client. Admins only.
// Uses Resend (resend.com). Secrets in Supabase → Edge Functions → Secrets:
//   RESEND_API_KEY   your Resend API key
//   INVOICE_FROM     e.g. "Your Agency <invoices@youragency.com>" (an address on a domain verified in Resend)
import { createClient } from "npm:@supabase/supabase-js@2.49.4";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
const esc = (s: unknown) =>
  String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]!));
const EMAIL_RE = /^[^\s@,;<>]+@[^\s@,;<>]+\.[^\s@,;<>]+$/;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);
  try {
    const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, {
      global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } },
    });
    const { data: who } = await sb.rpc("crm_whoami");
    if (who?.role !== "admin") return json({ error: "Admins only." }, 403);

    const key = Deno.env.get("RESEND_API_KEY");
    if (!key) return json({ error: "not_configured" }, 200);
    const from = Deno.env.get("INVOICE_FROM") || "Invoices <onboarding@resend.dev>";

    const { to, replyTo, subject, message, filename, pdfBase64, business } = await req.json();
    if (!EMAIL_RE.test(String(to ?? ""))) return json({ error: "Please enter a valid client email." }, 400);
    if (!pdfBase64 || String(pdfBase64).length > 7_000_000) return json({ error: "Invoice PDF missing or too large." }, 400);

    const html = `<div style="font-family:Arial,sans-serif;font-size:15px;color:#2a1f18;line-height:1.6;max-width:560px">
      ${esc(message).replace(/\n/g, "<br>")}
      <p style="color:#8c7d71;font-size:13px;margin-top:24px">The invoice is attached as a PDF.<br>— ${esc(business || "")}</p></div>`;

    const res = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        from,
        to: [to],
        ...(replyTo && EMAIL_RE.test(replyTo) ? { reply_to: replyTo } : {}),
        subject: String(subject || "Invoice").slice(0, 200),
        html,
        attachments: [{ filename: String(filename || "invoice.pdf").replace(/[^\w.\- ]/g, "_"), content: pdfBase64 }],
      }),
    });
    const out = await res.json().catch(() => ({}));
    if (!res.ok) {
      console.error("Resend error", res.status, out);
      return json({ error: out?.message || "Email service refused the message." }, 502);
    }
    return json({ ok: true, id: out?.id });
  } catch (e) {
    console.error(e);
    return json({ error: "Something went wrong sending the email." }, 500);
  }
});
