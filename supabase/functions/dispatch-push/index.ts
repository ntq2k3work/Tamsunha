import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

type PushDelivery = {
  delivery_id: string;
  notification_type: 'encouragement' | 'message';
  push_token: string;
  platform: 'android' | 'ios';
  attempt_count: number;
};

type FirebaseServiceAccount = {
  client_email: string;
  private_key: string;
  project_id: string;
};

const encoder = new TextEncoder();
let cachedAccessToken: string | null = null;
let cachedAccessTokenExpiresAt = 0;

const json = (status: number, body: Record<string, unknown>) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json; charset=utf-8' },
  });

function base64Url(bytes: Uint8Array): string {
  let binary = '';
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll('+', '-').replaceAll('/', '_').replace(/=+$/g, '');
}

function encodeJson(value: Record<string, unknown>): string {
  return base64Url(encoder.encode(JSON.stringify(value)));
}

function decodePem(value: string): Uint8Array {
  const normalized = value.replace(/\\n/g, '\n').replace(/-----[^-]+-----/g, '').replace(/\s/g, '');
  const binary = atob(normalized);
  return Uint8Array.from(binary, (character) => character.charCodeAt(0));
}

function equalSecret(actual: string, expected: string): boolean {
  const actualBytes = encoder.encode(actual);
  const expectedBytes = encoder.encode(expected);
  if (actualBytes.length !== expectedBytes.length) return false;
  let difference = 0;
  for (let index = 0; index < actualBytes.length; index++) {
    difference |= actualBytes[index] ^ expectedBytes[index];
  }
  return difference === 0;
}

async function getFirebaseAccessToken(account: FirebaseServiceAccount): Promise<string> {
  if (cachedAccessToken && Date.now() < cachedAccessTokenExpiresAt - 60_000) {
    return cachedAccessToken;
  }

  const now = Math.floor(Date.now() / 1000);
  const unsignedToken = `${encodeJson({ alg: 'RS256', typ: 'JWT' })}.${encodeJson({
    iss: account.client_email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
  })}`;
  const signingKey = await crypto.subtle.importKey(
    'pkcs8',
    decodePem(account.private_key),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const signature = new Uint8Array(
    await crypto.subtle.sign('RSASSA-PKCS1-v1_5', signingKey, encoder.encode(unsignedToken)),
  );
  const assertion = `${unsignedToken}.${base64Url(signature)}`;
  const response = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion,
    }),
  });
  if (!response.ok) throw new Error('FIREBASE_AUTH_UNAVAILABLE');

  const tokenResponse = await response.json();
  if (typeof tokenResponse.access_token !== 'string' ||
      typeof tokenResponse.expires_in !== 'number') {
    throw new Error('FIREBASE_AUTH_UNAVAILABLE');
  }
  cachedAccessToken = tokenResponse.access_token;
  cachedAccessTokenExpiresAt = Date.now() + tokenResponse.expires_in * 1000;
  return cachedAccessToken;
}

function messageFor(delivery: PushDelivery) {
  const encouragement = delivery.notification_type === 'encouragement';
  const collapseKey = encouragement ? 'tn_encouragement' : 'tn_message';
  return {
    message: {
      token: delivery.push_token,
      notification: {
        title: 'Tường Nhỏ',
        body: encouragement
          ? 'Bạn vừa nhận được một lời động viên trong Tường Nhỏ.'
          : 'Bạn có một lời nhắn mới trong Tường Nhỏ.',
      },
      data: {
        event_type: encouragement ? 'encouragement_received' : 'new_message',
        route: '/inbox',
      },
      android: {
        priority: 'normal',
        ttl: '86400s',
        collapse_key: collapseKey,
        notification: { tag: collapseKey },
      },
      apns: {
        headers: {
          'apns-push-type': 'alert',
          'apns-priority': '5',
          'apns-expiration': String(Math.floor(Date.now() / 1000) + 86_400),
          'apns-collapse-id': collapseKey,
        },
        payload: { aps: { sound: 'default' } },
      },
    },
  };
}

function firebaseErrorCode(body: unknown): string {
  if (typeof body !== 'object' || body === null || !('error' in body)) return 'UNKNOWN';
  const error = (body as { error?: { status?: unknown; details?: unknown } }).error;
  const details = Array.isArray(error?.details) ? error.details : [];
  for (const detail of details) {
    if (typeof detail !== 'object' || detail === null || !('errorCode' in detail)) continue;
    const code = (detail as { errorCode?: unknown }).errorCode;
    if (code === 'UNREGISTERED' || code === 'INVALID_ARGUMENT') return code;
  }
  if (error?.status === 'UNAVAILABLE' || error?.status === 'INTERNAL') return error.status;
  return 'UNKNOWN';
}

function safeErrorCode(code: string): string {
  return ['UNREGISTERED', 'INVALID_ARGUMENT', 'UNAVAILABLE', 'INTERNAL'].includes(code)
    ? code
    : 'UNKNOWN';
}

Deno.serve(async (request: Request) => {
  if (request.method !== 'POST') return json(405, { error: { code: 'METHOD_NOT_ALLOWED' } });

  const dispatchSecret = Deno.env.get('PUSH_DISPATCH_SECRET');
  const suppliedSecret = request.headers.get('x-push-dispatch-secret') ?? '';
  if (!dispatchSecret || !equalSecret(suppliedSecret, dispatchSecret)) {
    return json(401, { error: { code: 'UNAUTHENTICATED' } });
  }

  let account: FirebaseServiceAccount;
  try {
    const rawAccount = Deno.env.get('FIREBASE_SERVICE_ACCOUNT_JSON');
    const parsed = rawAccount ? JSON.parse(rawAccount) : null;
    if (typeof parsed?.client_email !== 'string' ||
        typeof parsed?.private_key !== 'string' ||
        typeof parsed?.project_id !== 'string') {
      return json(503, { error: { code: 'PUSH_PROVIDER_UNAVAILABLE' } });
    }
    account = parsed as FirebaseServiceAccount;
  } catch (_) {
    return json(503, { error: { code: 'PUSH_PROVIDER_UNAVAILABLE' } });
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!supabaseUrl || !serviceKey) {
    return json(503, { error: { code: 'PUSH_QUEUE_UNAVAILABLE' } });
  }

  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data, error } = await admin.rpc('claim_push_deliveries', { p_limit: 50 });
  if (error || !Array.isArray(data)) {
    return json(503, { error: { code: 'PUSH_QUEUE_UNAVAILABLE' } });
  }

  let sent = 0;
  let invalidTokens = 0;
  let retried = 0;
  let failed = 0;
  const deliveries = data as PushDelivery[];

  await Promise.all(deliveries.map(async (delivery) => {
    let outcome: 'sent' | 'invalid_token' | 'retry' = 'retry';
    let code = 'UNKNOWN';
    try {
      const accessToken = await getFirebaseAccessToken(account);
      const response = await fetch(
        `https://fcm.googleapis.com/v1/projects/${encodeURIComponent(account.project_id)}/messages:send`,
        {
          method: 'POST',
          headers: {
            Authorization: `Bearer ${accessToken}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify(messageFor(delivery)),
        },
      );
      if (response.ok) {
        outcome = 'sent';
      } else {
        let body: unknown = null;
        try {
          body = await response.json();
        } catch (_) {
          body = null;
        }
        code = safeErrorCode(firebaseErrorCode(body));
        outcome = code === 'UNREGISTERED' ? 'invalid_token' : 'retry';
      }
    } catch (_) {
      outcome = 'retry';
      code = 'UNKNOWN';
    }

    const { error: completionError } = await admin.rpc('complete_push_delivery', {
      p_delivery_id: delivery.delivery_id,
      p_outcome: outcome,
      p_error_code: code,
    });
    if (completionError) {
      failed++;
      return;
    }
    if (outcome === 'sent') sent++;
    else if (outcome === 'invalid_token') invalidTokens++;
    else retried++;
  }));

  return json(200, {
    data: { claimed: deliveries.length, sent, invalidTokens, retried, failed },
  });
});
