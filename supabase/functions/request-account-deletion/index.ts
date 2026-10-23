import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, apikey, content-type, x-client-info',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const json = (status: number, body: Record<string, unknown>) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json; charset=utf-8' },
  });

Deno.serve(async (request: Request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (request.method !== 'POST') return json(405, { error: { code: 'METHOD_NOT_ALLOWED' } });

  const authorization = request.headers.get('Authorization') ?? '';
  const tokenMatch = /^Bearer\s+(.+)$/i.exec(authorization);
  if (!tokenMatch) return json(401, { error: { code: 'UNAUTHENTICATED' } });
  const accessToken = tokenMatch[1];

  let input: { confirm?: unknown; client_request_id?: unknown };
  try {
    input = await request.json();
  } catch (_) {
    return json(400, { error: { code: 'INVALID_INPUT' } });
  }
  if (input.confirm !== true || typeof input.client_request_id !== 'string' ||
      !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(input.client_request_id)) {
    return json(400, { error: { code: 'INVALID_INPUT' } });
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const publicKey = Deno.env.get('SUPABASE_ANON_KEY') ?? Deno.env.get('SUPABASE_PUBLISHABLE_KEY');
  const secretKey = Deno.env.get('SUPABASE_SECRET_KEY') ?? Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!supabaseUrl || !publicKey || !secretKey) {
    return json(503, { error: { code: 'ACCOUNT_DELETION_UNAVAILABLE' } });
  }

  const caller = createClient(supabaseUrl, publicKey, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { Authorization: `Bearer ${accessToken}` } },
  });
  const { data: userData, error: userError } = await caller.auth.getUser(accessToken);
  if (userError || !userData.user) {
    return json(401, { error: { code: 'UNAUTHENTICATED' } });
  }

  const { data: deletion, error: deletionError } = await caller.rpc('request_account_deletion', {
    p_confirm: true,
    p_client_request_id: input.client_request_id,
  });
  if (deletionError || !deletion?.data?.request_id) {
    return json(409, {
      error: { code: deletion?.error?.code ?? 'ACCOUNT_DELETION_FAILED' },
    });
  }

  const admin = createClient(supabaseUrl, secretKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { error: revokeError } = await admin.auth.admin.signOut(accessToken, 'global');

  return json(200, {
    data: {
      request_id: deletion.data.request_id,
      status: deletion.data.status,
      account_access_disabled: true,
      refresh_sessions_revoked: revokeError == null,
    },
  });
});
