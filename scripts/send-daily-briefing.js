/**
 * Sends the daily briefing push notification for the Assistente Pessoal app.
 *
 * Runs on a schedule (see .github/workflows/daily-briefing.yml), reads every
 * saved push subscription from Firestore, and for whoever's local time
 * currently matches their chosen "briefingTime", sends one push summarizing
 * pending tasks, today's routines, and (if recently cached by the app)
 * today's calendar events.
 *
 * Authentication: this script does NOT use a downloaded service account key.
 * It relies on Workload Identity Federation — the workflow's
 * "google-github-actions/auth" step exchanges GitHub's OIDC token for a
 * short-lived Google credential scoped to the github-actions-briefing
 * service account and writes it to a file referenced by
 * GOOGLE_APPLICATION_CREDENTIALS. Nothing secret is stored in this repo.
 *
 * Note: we talk to Firestore via the plain @google-cloud/firestore client
 * (not firebase-admin). firebase-admin's own credential loader only
 * understands service-account/authorized-user JSON and rejects WIF-style
 * "external_account" credential files ("Invalid contents in the
 * credentials file" / "invalid-credential"). @google-cloud/firestore uses
 * google-auth-library directly under the hood, which DOES support
 * external_account/WIF out of the box via Application Default Credentials
 * - so no extra wiring is needed here.
 *
 * Required environment variables (set as GitHub Actions secrets):
 *   VAPID_PUBLIC_KEY          Web Push public key (also embedded in index.html)
 *   VAPID_PRIVATE_KEY         Web Push private key (keep secret!)
 *   VAPID_SUBJECT             mailto: address used to identify the sender
 */
const { Firestore } = require('@google-cloud/firestore');
const webpush = require('web-push');

const FIREBASE_PROJECT_ID = 'assistente-ee1f4';

function required(name) {
  const v = process.env[name];
  if (!v) {
    console.error(`Missing required env var: ${name}`);
    process.exit(1);
  }
  return v;
}

const vapidPublic = required('VAPID_PUBLIC_KEY');
const vapidPrivate = required('VAPID_PRIVATE_KEY');
const vapidSubject = process.env.VAPID_SUBJECT || 'mailto:tiagocamargos@tocsmartgroup.com';

const db = new Firestore({ projectId: FIREBASE_PROJECT_ID });

webpush.setVapidDetails(vapidSubject, vapidPublic, vapidPrivate);

const AREA_LABELS = { deus: 'Deus', pessoal: 'Pessoal', familia: 'Família', financas: 'Finanças', negocios: 'Negócios' };

function isFamily(uid) {
  return uid === 'tiago' || uid === 'monique';
}

function localHHMM(timezone) {
  return new Intl.DateTimeFormat('en-GB', { timeZone: timezone, hour: '2-digit', minute: '2-digit', hour12: false }).format(new Date());
}

function localDateStr(timezone) {
  // en-CA formats as YYYY-MM-DD
  return new Intl.DateTimeFormat('en-CA', { timeZone: timezone }).format(new Date());
}

function minutesSinceMidnight(hhmm) {
  const [h, m] = hhmm.split(':').map(Number);
  return h * 60 + m;
}

// Cron runs every 10 minutes — treat a match as "within 10 minutes after the target time"
// so nobody gets skipped due to scheduling jitter.
function isDueNow(briefingTime, timezone) {
  const nowHHMM = localHHMM(timezone);
  const diff = minutesSinceMidnight(nowHHMM) - minutesSinceMidnight(briefingTime);
  return diff >= 0 && diff < 10;
}

function todayLocalDow(timezone) {
  const parts = new Intl.DateTimeFormat('en-US', { timeZone: timezone, weekday: 'short' }).format(new Date());
  const map = { Sun: 0, Mon: 1, Tue: 2, Wed: 3, Thu: 4, Fri: 5, Sat: 6 };
  return map[parts] ?? new Date().getDay();
}

function isRoutineDue(r, dow) {
  if (r.freq === 'daily') return true;
  return Array.isArray(r.weekdays) && r.weekdays.includes(dow);
}

async function buildBriefing(uid, dateStr, dow) {
  const parts = [];

  // Tasks: personal (new per-user subcollection) + (if family) household shared
  const collectionPaths = [`users/${uid}/tasks`];
  if (isFamily(uid)) collectionPaths.push('shared_tasks');
  let pending = [];
  for (const path of collectionPaths) {
    const snap = await db.collection(path).get();
    snap.forEach((doc) => {
      const t = doc.data();
      if (!t.done) pending.push(t);
    });
  }
  const urgentCount = pending.filter((t) => t.urgency === 'urgent').length;
  if (pending.length) {
    parts.push(`${pending.length} tarefa${pending.length > 1 ? 's' : ''} pendente${pending.length > 1 ? 's' : ''}${urgentCount ? ` (${urgentCount} urgente${urgentCount > 1 ? 's' : ''})` : ''}`);
  }

  // Routines due today, not yet done
  try {
    const rSnap = await db.collection(`users/${uid}/routines`).get();
    let dueToday = 0;
    rSnap.forEach((doc) => {
      const r = doc.data();
      if (isRoutineDue(r, dow) && !(r.completions && r.completions[dateStr])) dueToday++;
    });
    if (dueToday) parts.push(`${dueToday} rotina${dueToday > 1 ? 's' : ''} de hoje`);
  } catch (e) {
    /* ignore */
  }

  // Calendar (only if the app cached today's events recently)
  try {
    const calDoc = await db.doc(`calendar_cache/${uid}`).get();
    if (calDoc.exists) {
      const cal = calDoc.data();
      if (cal.date === dateStr && Array.isArray(cal.events) && cal.events.length) {
        const first = cal.events.slice(0, 2).map((e) => `${e.time || 'dia todo'} ${e.title}`).join(', ');
        parts.push(`${cal.events.length} compromisso${cal.events.length > 1 ? 's' : ''}: ${first}`);
      }
    }
  } catch (e) {
    /* ignore */
  }

  if (!parts.length) return 'Nada pendente por aqui. Bom dia! ✦';
  return parts.join(' · ');
}

// ── CASA: lembretes das tarefas diárias partilhadas do lar ──────────────
// A aba "Casa" do app guarda em household/casa a lista de tarefas do dia
// (algumas com hora-limite) e, em household/casa/days/YYYY-MM-DD, quem já
// marcou o quê. Este job (a cada 10 min) avisa TODOS os membros da casa que
// têm push ativado quando uma tarefa com hora-limite ainda não está marcada:
// uma vez 30 minutos antes ("pre") e outra à própria hora ("due"). O que já
// foi avisado fica registado em days/{data}.reminded para nunca repetir.
const CASA_PRE_MIN = 30;
async function sendCasaReminders(subsByUid) {
  const houseSnap = await db.doc('household/casa').get();
  if (!houseSnap.exists) return;
  const house = houseSnap.data();
  const timezone = house.timezone || 'Europe/Lisbon';
  const today = localDateStr(timezone);
  const nowMin = minutesSinceMidnight(localHHMM(timezone));
  const dayRef = db.doc(`household/casa/days/${today}`);
  const daySnap = await dayRef.get();
  const day = daySnap.exists ? daySnap.data() : {};
  const done = day.done || {};
  const reminded = day.reminded || {};
  const memberUids = Object.keys(house.members || {});
  const targets = memberUids.map((uid) => subsByUid[uid]).filter(Boolean);

  for (const task of house.tasks || []) {
    if (!task || !task.label || !task.time || done[task.id]) continue;
    const tMin = minutesSinceMidnight(task.time);
    const slots = [
      { key: 'pre', at: tMin - CASA_PRE_MIN, title: '🏡 Casa — daqui a 30 min', body: `${task.label} (até às ${task.time})` },
      { key: 'due', at: tMin, title: '🏡 Casa — hora-limite', body: `${task.label} ainda não está marcado (${task.time})` }
    ];
    for (const slot of slots) {
      if (slot.at < 0) continue;
      const diff = nowMin - slot.at;
      if (diff < 0 || diff >= 10) continue;
      const rkey = `${task.id}_${slot.key}`;
      if (reminded[rkey]) continue;
      let sent = 0;
      for (const doc of targets) {
        const sub = doc.data();
        try {
          await webpush.sendNotification(sub.subscription, JSON.stringify({ title: slot.title, body: slot.body, url: './?tab=casa' }));
          sent++;
        } catch (err) {
          if (err.statusCode === 404 || err.statusCode === 410) {
            await doc.ref.delete();
          } else {
            console.error(`Casa: failed push to ${doc.id}:`, err.message);
          }
        }
      }
      await dayRef.set({ date: today, reminded: { [rkey]: true } }, { merge: true });
      console.log(`Casa: reminder "${rkey}" (${task.label}) sent to ${sent} member(s).`);
    }
  }
}

async function main() {
  const subsSnap = await db.collection('push_subscriptions').get();
  const subsByUid = {};
  subsSnap.forEach((d) => { subsByUid[d.data().uid || d.id] = d; });
  try {
    await sendCasaReminders(subsByUid);
  } catch (e) {
    console.error('Casa reminders failed:', e.message);
  }
  if (subsSnap.empty) {
    console.log('No push subscriptions found.');
    return;
  }

  for (const doc of subsSnap.docs) {
    const sub = doc.data();
    const uid = sub.uid || doc.id;
    const timezone = sub.timezone || 'Europe/Lisbon';
    const briefingTime = sub.briefingTime || '07:00';
    const todayStr = localDateStr(timezone);

    if (sub.lastSent === todayStr) continue; // already sent today
    if (!isDueNow(briefingTime, timezone)) continue; // not their time yet

    const dow = todayLocalDow(timezone);
    let body;
    try {
      body = await buildBriefing(uid, todayStr, dow);
    } catch (e) {
      console.error(`Failed building briefing for ${uid}:`, e.message);
      continue;
    }

    const payload = JSON.stringify({
      title: `🔔 Bom dia${sub.name ? ', ' + sub.name : ''}!`,
      body,
      url: './?quick=1'
    });

    try {
      await webpush.sendNotification(sub.subscription, payload);
      await doc.ref.update({ lastSent: todayStr });
      console.log(`Sent briefing to ${uid} (${timezone} ${briefingTime}).`);
    } catch (err) {
      if (err.statusCode === 404 || err.statusCode === 410) {
        console.log(`Subscription for ${uid} is gone, removing it.`);
        await doc.ref.delete();
      } else {
        console.error(`Failed to send push to ${uid}:`, err.message);
      }
    }
  }
}

main()
  .then(() => process.exit(0))
  .catch((e) => {
    console.error(e);
    process.exit(1);
  });
