// App configuration — all values here are public (safe to be in the repo).
// Edit this file once; updating index.html later will not overwrite it.
window.APP_CONFIG = {
  SUPABASE_URL: "https://bmafawswwrcckwfoopem.supabase.co",
  SUPABASE_KEY: "sb_publishable_8VpPZdTpb4MIyjgKGZ3o4g_gusWcXpW", // publishable key only, never the secret key
  VAPID_PUBLIC_KEY:
    "BBQrcLFL8f7Mwu5s6O2qHE_q-bGY_HeMvJRL1h2Pni3BdQJwgFe4DzhA4NOf_w1ZCKsu8DXdQaXmhIRCGfwJU_Q", // the PUBLIC push key
  GOOGLE_CLIENT_ID:
    "38599321289-nejcjg52rae4e53lbiuu6ifhst6ovqfk.apps.googleusercontent.com", // Google OAuth Web client ID (public) - fixes sign-in inside the iPhone home-screen app
  MUSIC_URL: "theme_song.mp3", // optional: file name of a background song in the repo, e.g. 'music.mp3' (leave empty for no music button)
  VOICE_FILES: {
    // score_taken: "voice/score_taken.mp3", // no longer used: the same score may now be picked by several players
    // guess_window_closed: 'voice/guess_window_closed.mp3',
  },
};
