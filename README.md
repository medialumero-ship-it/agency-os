# Agency OS

Your agency's CRM: projects, editors, clients, leaderboard and finance in one page.

## For the team

- **Open it:** use the link your admin sends you (bookmark it, and add it to your phone's home screen if you like).
- **Editors:** pick the **Editor** tab and sign in with your name and the password your admin gave you. Change your password in **⚙ Settings** after your first sign-in.
- **Clients:** pick the **Client** tab and sign in with your brand name and password.
- Changes save automatically and show up for everyone straight away.

## For the admin

- Sign in on the **Admin** tab. Change the admin password any time in **⚙ Settings**.
- **Add an editor:** ⚙ Settings → add them to a team or as an individual. A login box pops up with their starting password. Copy it and send it to them privately.
- **Add a client:** ⚙ Settings → client accounts.
- **Reset someone's password:** ⚙ Settings → type a new one next to their name → Update. Passwords are stored scrambled, so the old one can't be shown.
- After 10 wrong passwords in a row, that login is paused for 15 minutes.

## Invoices (admin only)

- Open the **Invoices** tab, then click **＋ New invoice**. Fill in the client, the lines and your payment details. The preview on the right shows exactly what the client will get.
- **＋ Add finished projects** adds that client's *Done* projects for the selected month as invoice lines.
- **⬇ Download PDF** saves the invoice to your computer.
- **✉ Email to client** sends the PDF straight to the client's inbox once email sending is set up (see Technical notes). Until then, it downloads the PDF and opens your own email app with the message written for you; just attach the PDF and press Send.
- Your business details, payment info and each client's email are remembered for next time. Mark invoices as **paid** to keep the totals at the top correct.

## Work Log (admin only)

**Editors (paid per project)**
- On the **Editors** board, set each project's **Client** while you assign the editor. Only admins see the Client column. Editors never receive client names at all.
- In **Work Log**, every project assigned that month is listed under its editor. Type the **minutes**, and the pay is worked out automatically.
- Rates are used in this order:
  1. a rate typed on that one project
  2. the editor's special rate for that client (under **⚙ Rates**)
  3. the editor's usual rate
  4. the default rate for all editors
- Add an **Extra** amount on any project that needs bonus pay, such as an advanced edit.

**Designers and scriptwriters**
- Pick **Designer** or **Scriptwriter**, choose the person (or **＋ Add a new…**), enter thumbnails or scripts, then click **＋ Add**. Set a default pay per thumbnail or script, or a different rate per person.

**Month-end**
- Use **‹ ›** to switch months. **⬇ Download month (Excel)** gives every editor project with minutes, rate, extra and pay, plus designer and writer totals.

## Who sees what

| | Admin | Editor | Client |
|---|---|---|---|
| Project board | ✅ all | ✅ all (edits their own) | only their own projects |
| Revenue, points, who's assigned | ✅ edit | view only | – |
| Finance, salaries, expenses, leads | ✅ | – | – |
| Invoices, Work Log (minutes, thumbnails, scripts, pay) | ✅ | – | – |
| Which client a project is for | ✅ | – | their own |
| Logins | ✅ | their own | their own |

These rules are enforced by the database, not just hidden on screen.

## Technical notes

- `index.html`: the whole app, hosted free on GitHub Pages.
- `supabase/schema.sql`: database tables and access rules. You can run it again safely.
- `supabase/functions/ai-robot`: the AI robot. It only answers signed-in users. It needs an `OPENAI_API_KEY` secret in Supabase (Edge Functions → Secrets).
- `supabase/functions/send-invoice`: emails invoices with the PDF attached, using Resend (resend.com). To turn it on, add two secrets in Supabase (Edge Functions → Secrets): `RESEND_API_KEY`, and `INVOICE_FROM` (for example `Your Agency <invoices@youragency.com>`, on a domain you've verified in Resend).
- The Supabase URL and public key in `index.html` are meant to be public. The database rules keep the data safe.
