# Agency OS

Your agency's CRM: projects, editors, clients, leaderboard and finance in one page.

## For the team

- **Open it:** use the link your admin sends you (bookmark it, and add it to your phone's home screen if you like).
- **Editors:** pick the **Editor** tab and sign in with your name and the password your admin gave you. Change your password in **⚙ Settings** after your first sign-in.
  - On **My Projects**, click **Add min** to enter the minutes you edited. Minutes lock once the video is sent to the client (status *Client Review* or *Done*). Ask the admin if a number needs fixing.
  - The **Leaderboard** ranks editors by minutes of videos delivered to clients this month.
- **Clients:** pick the **Client** tab and sign in with your brand name and password.
- Changes save automatically.

## For the admin

- Sign in on the **Admin** tab. Change the admin password any time in **⚙ Settings**.
- **Add an editor:** ⚙ Settings → add them to a team or as an individual. A login box pops up with their starting password. Copy it and send it to them privately.
- **Add a client:** ⚙ Settings → client accounts.
- **Reset someone's password:** ⚙ Settings → type a new one next to their name → Update. Passwords are stored scrambled, so the old one can't be shown.
- After 10 wrong passwords in a row, that login is paused for 15 minutes.

## Client rates, payments and invoices (admin only)

**Client rates.** On the **Clients** page, set what each client pays under 🔒 **Charges**: **per minute** (for example $2/min) or **flat per video**. Only you can see this.

**Automatic amounts.** When a video goes to the client (status **Client Review** or **Done**), its amount is worked out automatically (the client's rate × the editor's minutes, or the flat price). It appears as **unpaid** for that client in **Invoices** and counts in Finance revenue. You don't type revenue yourself. If you do type a revenue by hand on a project, your number is kept.

**Client payments**, at the top of the Invoices tab:
- **Unpaid**, **Paid this month** and **Paid all time**, with a row per client. Open a client to see each video and mark it **✓ Paid**, or use **Mark all unpaid as paid**.
- Paid videos keep their amount even if you change the client's rate later.

**⚡ Create an invoice from recent work:** pick the client and **the last 7 days**, **14 days**, **month** or **all unpaid work**. The invoice is filled in with every unpaid video from that period, priced from the client's rate. Check it, then **Save**, **Download PDF** or **Email to client**. Marking that invoice paid marks its videos paid.

**Invoices**
- **＋ New invoice** builds one by hand. **＋ Add unpaid finished projects** adds that client's unpaid videos.
- **⬇ Download PDF** saves it. **✉ Email to client** sends it once email sending is set up (see Technical notes). Until then it downloads the PDF and opens your own email app with the message written for you.

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
| Project board | ✅ all | ✅ all projects (edits their own) | only their own projects |
| Minutes | ✅ edit | their own (locked once sent), and totals on the leaderboard | – |
| Which client a project is for | ✅ | – | their own |
| Client rates, revenue, unpaid/paid, invoices | ✅ | – | – |
| Finance, salaries, expenses, leads, Work Log pay | ✅ | – | – |
| Logins | ✅ | their own | their own |

These rules are enforced by the database, not just hidden on screen. Editors and clients never receive the hidden information at all, even through the browser's developer tools.

**Other protections**
- Editors see full details only for **their own** projects. For other editors' projects they get just the name, status and minutes the leaderboard needs: no titles, notes, links or dates.
- Passwords need at least 8 characters. They're scrambled and kept in a table no one can read, not even the admin's browser.
- Wrong passwords: 5 tries per browser every 15 minutes, and 20 per account from new browsers. A browser that has signed in to an account before is never locked out by other people's guessing.
- Admin logins last 7 days, others 30. Resetting someone's password or deleting their account signs them out everywhere at once.
- Anything editors or clients type is checked by the database (IDs, statuses, dates, minutes) and shown as plain text, so it can't run code on the admin's screen.
- The page loads its code only from this site (`vendor/`, with fingerprint checks), talks only to your own database, and can't be embedded by other websites. Email and phone sign-up are switched off in Supabase.

**What software can't stop:** an editor sees the footage they edit, so a logo or brand in the video itself is visible to them. Keep client names out of project titles, notes, file names and shared-folder names (use a code like "NW-014" instead).

## Technical notes

- `index.html`: the whole app, hosted free on GitHub Pages.
- `supabase/schema.sql`: database tables and access rules. You can run it again safely.
- `supabase/functions/ai-robot`: the AI robot. It only answers signed-in users. It needs an `OPENAI_API_KEY` secret in Supabase (Edge Functions → Secrets).
- `supabase/functions/send-invoice`: emails invoices with the PDF attached, using Resend (resend.com). To turn it on, add two secrets in Supabase (Edge Functions → Secrets): `RESEND_API_KEY`, and `INVOICE_FROM` (for example `Your Agency <invoices@youragency.com>`, on a domain you've verified in Resend).
- The Supabase URL and public key in `index.html` are meant to be public. The database rules keep the data safe.
