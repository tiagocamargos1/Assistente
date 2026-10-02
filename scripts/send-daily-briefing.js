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
// Desde 10/09/2026 há uma casa por utilizador (household/{hid}); percorre todas.
async function sendCasaReminders(subsByUid) {
  const housesSnap = await db.collection('household').get();
  for (const houseSnap of housesSnap.docs) {
    try { await sendHouseReminders(houseSnap, subsByUid); }
    catch (err) { console.error('Casa reminders failed for one house:', err.message); }
  }
}
async function sendHouseReminders(houseSnap, subsByUid) {
  const hid = houseSnap.id;
  const house = houseSnap.data();
  const timezone = house.timezone || 'Europe/Lisbon';
  const today = localDateStr(timezone);
  const nowMin = minutesSinceMidnight(localHHMM(timezone));
  const dayRef = db.doc(`household/${hid}/days/${today}`);
  const daySnap = await dayRef.get();
  const day = daySnap.exists ? daySnap.data() : {};
  const done = day.done || {};
  const reminded = day.reminded || {};
  // Só membros reais (e-mail na lista `emails` da casa) recebem lembretes —
  // o mapa `members` é escrito pelos clientes e não basta para decidir a quem enviar.
  const houseEmails = (house.emails || []).map((e) => String(e).toLowerCase());
  const memberUids = Object.entries(house.members || {})
    .filter(([, m]) => m && m.email && houseEmails.includes(String(m.email).toLowerCase()))
    .map(([uid]) => uid);
  const targets = memberUids.map((uid) => subsByUid[uid]).filter(Boolean);
  if (!targets.length) return;

  for (const task of house.tasks || []) {
    if (!task || !task.label || !task.time || done[task.id]) continue;
    if (!/^([01]\d|2[0-3]):[0-5]\d$/.test(String(task.time))) continue;
    const label = String(task.label).slice(0, 80);
    const tMin = minutesSinceMidnight(task.time);
    const slots = [
      { key: 'pre', at: tMin - CASA_PRE_MIN, title: '🏡 Casa — daqui a 30 min', body: `${label} (até às ${task.time})` },
      { key: 'due', at: tMin, title: '🏡 Casa — hora-limite', body: `${label} ainda não está marcado (${task.time})` }
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
            console.error('Casa: failed push:', err.statusCode || err.message);
          }
        }
      }
      await dayRef.set({ date: today, reminded: { [rkey]: true } }, { merge: true });
      console.log(`Casa reminder sent to ${sent} member(s).`);
    }
  }
}

async function main() {
  const subsSnap = await db.collection('push_subscriptions').get();
  const subsByUid = {};
  // A identidade é SEMPRE o id do documento (as regras garantem que só o próprio o escreve);
  // o campo `uid` dentro do documento é ignorado (podia ser forjado para receber o briefing de outra pessoa).
  subsSnap.forEach((d) => { subsByUid[d.id] = d; });
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
    const uid = doc.id;
    const timezone = typeof sub.timezone === 'string' && sub.timezone.length < 64 ? sub.timezone : 'Europe/Lisbon';
    const briefingTime = /^([01]\d|2[0-3]):[0-5]\d$/.test(String(sub.briefingTime || '')) ? sub.briefingTime : '07:00';
    let todayStr, dow;
    try {
      todayStr = localDateStr(timezone);
      if (sub.lastSent === todayStr) continue; // already sent today
      if (!isDueNow(briefingTime, timezone)) continue; // not their time yet
      dow = todayLocalDow(timezone);
    } catch (e) {
      console.error('Subscription with invalid time settings skipped.');
      continue;
    }
    let body;
    try {
      body = await buildBriefing(uid, todayStr, dow);
    } catch (e) {
      console.error('Failed building a briefing:', e.message);
      continue;
    }

    const payload = JSON.stringify({
      title: `🔔 Bom dia${sub.name ? ', ' + String(sub.name).slice(0, 30) : ''}!`,
      body,
      url: './?quick=1'
    });

    try {
      await webpush.sendNotification(sub.subscription, payload);
      await doc.ref.update({ lastSent: todayStr });
      console.log('Sent one briefing.');
    } catch (err) {
      if (err.statusCode === 404 || err.statusCode === 410) {
        console.log('A subscription is gone, removing it.');
        await doc.ref.delete();
      } else {
        console.error('Failed to send a briefing push:', err.statusCode || err.message);
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
