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
  // voice pools: one file is picked at random for each event (put the files in the voice/ folder)
  // exact = תוצאה מדויקת · direction = כיוון · miss = פספוס · no_guess = לא ניחש · reminder = תזכורת לנחש
  VOICE_POOLS: {
    exact: [
      "voice/exact/הרצל - אתה מוכר את החולצה.mp3",
      "voice/exact/הרצל - צחוק אחד הגדולים.mp3",
      "voice/exact/שאול - כל הכבוד שאתה בפסגה - סחטיין שאפו עליך.mp3",
      "voice/exact/שאול - כל הכבוד.mp3",
      "voice/exact/שלום - אלללללאאייייי.mp3",
      "voice/exact/שלום - הנה המדינה של המפגרים, עשה בול אחד נהיה גאון כדורגל.mp3",
      "voice/exact/שלום - יש רגעים שצריכים לשמור על צניעות.mp3",
      "voice/exact/שלום - כולה בול, עידן של יום חדש, את הכסף סופרים במדרגות.mp3",
    ],
    direction: [
      "voice/direction/הרצל - מסי עצבני.mp3",
      "voice/direction/שאול - אני מת על האופטימיות קוסמית.mp3",
      "voice/direction/שאול - ויסקה בארסה.mp3",
      "voice/direction/שלום - אני מודה שאני אין לי ציפיות, מה שיהיה יהיה.mp3",
      "voice/direction/שלום - חיקוי של קוף.mp3",
      "voice/direction/שלום - מסי עצבני.mp3",
      "voice/direction/שלום - סתם צחוק.mp3",
      "voice/direction/שלום - עיוני.mp3",
    ],
    miss: [
      "voice/miss/הרצל - דלביוב בלאט.mp3",
      "voice/miss/הרצל - עידו, אם אני נופל כולם נופלים.mp3",
      "voice/miss/שאול - אוי אוי את הפללייי.mp3",
      "voice/miss/שאול - הנה עוד פעם המדינה של המפגרים.mp3",
      "voice/miss/שאול - הפוך גוטה הפוך.mp3",
      "voice/miss/שאול - לא בדיוק מה שכתבת.mp3",
      "voice/miss/שלום - אוווו את הפליי.mp3",
      "voice/miss/שלום - אסי עד עכשיו מנסה ללחוץ ביטול.mp3",
      "voice/miss/שלום - אתה לא חד, תבדוק מה שאתה כותב ותחזור אליי.mp3",
      "voice/miss/שלום - כל פרסום הוא טוב, הכל טוב.mp3",
      "voice/miss/שלום - תבוא תעשה שיעורי בית בסוף שלום ייקח.mp3",
    ],
    no_guess: [
      "voice/no_guess/שלום - יא מטומטם , ביקשו לתת תוצאה לא לתת פרשנות אכפת לנו מה אתה חושב.mp3",
    ],
    reminder: [
      "voice/reminder/שלום - יא מטומטם , ביקשו לתת תוצאה לא לתת פרשנות אכפת לנו מה אתה חושב.mp3",
    ],
  },
};
