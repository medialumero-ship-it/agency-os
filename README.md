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

## Who sees what

| | Admin | Editor | Client |
|---|---|---|---|
| Project board | ✅ all | ✅ all (edits their own) | only their own projects |
| Revenue, points, who's assigned | ✅ edit | view only | – |
| Finance, salaries, expenses, leads | ✅ | – | – |
| Logins | ✅ | their own | their own |

These rules are enforced by the database, not just hidden on screen.

## Technical notes

- `index.html`: the whole app, hosted free on GitHub Pages.
- `supabase/schema.sql`: database tables and access rules. You can run it again safely.
- `supabase/functions/ai-robot`: the AI robot. It only answers signed-in users. It needs an `OPENAI_API_KEY` secret in Supabase (Edge Functions → Secrets).
- The Supabase URL and public key in `index.html` are meant to be public. The database rules keep the data safe.
