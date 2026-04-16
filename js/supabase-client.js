// ============================================================
//  Oswald Vision Capital — Supabase Client
//  Shared across: admin, performance, subscribe pages
// ============================================================
(function () {
  var SUPABASE_URL      = 'https://bnmjhmijhgxpjbrtwbdv.supabase.co';
  var SUPABASE_ANON_KEY = 'sb_publishable_wGAN6IdcQOzPdvN7uEcn2w_yHQlh_RK';

  if (!window.supabase || !window.supabase.createClient) {
    console.warn('[OVC] Supabase library not loaded — _db will be unavailable.');
    return;
  }

  window._db = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
  console.log('[OVC] Supabase client initialized.');
})();
