Runbook — make backend ingest & admin alerts work

Goal
- Ensure client fallbacks write events that backend or staff can see even when Cloud Functions are not deployed.

What I changed in code
- Client now writes fallback documents at these places:
  - `backend_ingest` — lightweight queue entry for orders, coupon claims, FCM alerts (multiple client code paths)
  - `admin_notifications`, `admin_alerts`, `admin_order_alerts` — client creates lightweight admin docs so staff UIs can see requests
  - `client_debug_logs` — written when callables or top-level writes fail (useful to diagnose permission/exception causes)
- Added Firestore rules (in `firestore.rules`) to allow authenticated users to CREATE the above collections while restricting read/update/delete to admins.

Required next steps (you must perform these from your machine)

1) Deploy Firestore rules
- From project root (PowerShell):
```powershell
firebase deploy --only firestore:rules
```
- Alternatively: open Firebase Console → Firestore → Rules → paste contents of `firestore.rules` and Publish.

2) (Optional) If you want server functions to process `backend_ingest` or react to `orders/` events, you must deploy Cloud Functions. Note: some Firebase projects require Blaze (billing) to enable Artifact Registry / Cloud Build APIs. If deploy fails with errors about enabling APIs or Blaze, you have options:
  - Upgrade project to Blaze (recommended for production). Then run:
```powershell
firebase deploy --only functions
```
  - Or run functions locally using the Firebase Emulator Suite (no Blaze needed) to test locally:
```powershell
# start emulator (from project root)
firebase emulators:start --only functions,firestore
```
  - If you can't/choose not to deploy functions, rely on client fallbacks + `backend_ingest` for operators to process events manually.

3) Run end-to-end test in app
- Sign-in as test user in app, place an order (checkout flow).
- After the flow finishes, open Firestore console and check these collections:
  - `client_debug_logs` — should contain debug entries if a callable or write failed
  - `backend_ingest` — should have an entry for the order/request
  - `orders/` — top-level order (if writable by client)
  - `users/{uid}/order_requests/` — fallback request if top-level orders write blocked
  - `admin_notifications`, `admin_alerts`, `admin_order_alerts` — staff-facing docs
  - `users/{uid}/alerts/` — user's individual alert for notifications

4) If you see no docs in Firestore after performing the test
- Open Firebase Console → Firestore → Rules → Monitor → Rejected requests; copy any denied request entries (they show the path and rule reason).
- Copy the error lines from your Flutter debug console (Terminal/IDE) while performing the checkout — the client prints debug logs for functions exceptions and fallbacks.

5) Share the following with me (so I can finish fixes):
- Screenshots of the Firestore collections listed above
- Any entries from `client_debug_logs` (copy/paste)
- Output from Firestore Rules Monitor showing denied requests (if any)
- Flutter debug console logs from the time you ran the flow

If you want me to tighten rules before you deploy
- I can modify `firestore.rules` to validate minimal schema for `backend_ingest` or `admin_alerts` (e.g., require `type` field and `createdAt` timestamp). Tell me to proceed and I'll prepare that stricter ruleset.

If you'd like I can also add a small admin dashboard script in `tools/` that periodically polls `backend_ingest` and shows new events for manual processing.

---
Notes
- I cannot run `firebase deploy` on your machine; you'll need to run the deploy command above and paste any errors here if they occur.
- After you deploy rules and run the test, paste the results and I'll iterate until everything shows up in Firestore and admin sees notifications.