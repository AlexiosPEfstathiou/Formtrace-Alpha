// ============================================================
// FormTrace Coach — store.supabase.js
// Drop-in backend for the app's data layer, backed by Supabase.
// Exposes window.store with the same surface the app already uses,
// plus auth + video helpers the multi-user alpha needs.
//
// Load order in index.html (all before the app code):
//   <script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2"></script>
//   <script src="config.js"></script>
//   <script src="store.supabase.js"></script>
// ============================================================
(function () {
  const { SUPABASE_URL, SUPABASE_ANON_KEY } = window.FT_CONFIG || {};
  if (!SUPABASE_URL || SUPABASE_URL.includes("YOUR-PROJECT")) {
    alert("FormTrace: edit config.js with your Supabase URL and anon key.");
  }
  const sb = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

  // ---- small helpers ----
  function must(res) {
    if (res.error) throw res.error;
    return res.data;
  }
  function uid() {
    return sb.auth.getUser().then(r => r.data.user && r.data.user.id);
  }

  // ==========================================================
  // AUTH
  // ==========================================================
  const auth = {
    async signUp(email, password, displayName) {
      return must(await sb.auth.signUp({
        email, password,
        options: { data: { display_name: displayName } }
      }));
    },
    async signIn(email, password) {
      return must(await sb.auth.signInWithPassword({ email, password }));
    },
    async signOut() { return must(await sb.auth.signOut()); },
    async currentUser() {
      const r = await sb.auth.getUser();
      return r.data.user || null;
    },
    onChange(cb) { sb.auth.onAuthStateChange((_e, session) => cb(session)); },
    async myProfile() {
      const u = await this.currentUser();
      if (!u) return null;
      return must(await sb.from("profiles").select("*").eq("id", u.id).single());
    },
    async updateProfile(patch) {
      const u = await this.currentUser();
      return must(await sb.from("profiles").update(patch).eq("id", u.id).select().single());
    }
  };

  // ==========================================================
  // VIDEO (Supabase Storage)  — bucket 'videos', path {uid}/{uuid}.webm
  // upload() takes a Blob (from MediaRecorder) and returns its storage path.
  // signedUrl() turns a stored path into a playable, time-limited URL.
  // ==========================================================
  const video = {
    async upload(blob, ext = "webm") {
      const u = await auth.currentUser();
      if (!u) throw new Error("Not signed in");
      const path = `${u.id}/${crypto.randomUUID()}.${ext}`;
      const res = await sb.storage.from("videos")
        .upload(path, blob, { contentType: blob.type || "video/webm", upsert: false });
      if (res.error) throw res.error;
      return path;
    },
    async signedUrl(path, seconds = 3600) {
      if (!path) return null;
      const res = await sb.storage.from("videos").createSignedUrl(path, seconds);
      if (res.error) throw res.error;
      return res.data.signedUrl;
    },
    async remove(path) {
      if (!path) return;
      await sb.storage.from("videos").remove([path]);
    }
  };

  // ==========================================================
  // COACH APPLICATIONS
  // ==========================================================
  const coachApps = {
    async apply(form) {
      const u = await auth.currentUser();
      return must(await sb.from("coach_applications")
        .insert({ user_id: u.id, ...form }).select().single());
    },
    async mine() {
      const u = await auth.currentUser();
      return must(await sb.from("coach_applications")
        .select("*").eq("user_id", u.id).order("created_at", { ascending: false }));
    },
    // admin
    async pending() {
      return must(await sb.from("coach_applications")
        .select("*, profiles!coach_applications_user_id_fkey(display_name,city)")
        .eq("status", "pending").order("created_at"));
    },
    async approve(appId) {
      return must(await sb.rpc("approve_coach_application", { app_id: appId }));
    },
    async reject(appId) {
      return must(await sb.from("coach_applications")
        .update({ status: "rejected", reviewed_at: new Date().toISOString() })
        .eq("id", appId).select().single());
    }
  };

  // ==========================================================
  // GENERIC TABLE HELPERS
  // Thin CRUD wrappers so the app can read/write each table.
  // RLS (server-side) enforces who can see/change what.
  // ==========================================================
  function table(name) {
    return {
      async list(match) {
        let q = sb.from(name).select("*");
        if (match) Object.entries(match).forEach(([k, v]) => { q = q.eq(k, v); });
        return must(await q.order("created_at", { ascending: false }));
      },
      async get(id) {
        return must(await sb.from(name).select("*").eq("id", id).single());
      },
      async add(row) {
        return must(await sb.from(name).insert(row).select().single());
      },
      async update(id, patch) {
        return must(await sb.from(name).update(patch).eq("id", id).select().single());
      },
      async remove(id) {
        return must(await sb.from(name).delete().eq("id", id));
      }
    };
  }

  // ==========================================================
  // PUBLIC SURFACE  (window.store)
  // ==========================================================
  window.store = {
    _sb: sb,                 // escape hatch for realtime / advanced use
    auth,
    video,
    coachApps,

    // library (coach)
    exercises: table("exercises"),
    workouts:  table("workouts"),

    // marketplace
    listings:  table("listings"),
    offers:    table("offers"),

    // relationship + delivery
    engagements:      table("engagements"),
    assignedWorkouts: table("assigned_workouts"),
    submissions:      table("submissions"),
    reviews:          table("reviews"),
    ratings:          table("ratings"),

    // trainee logging
    logs: table("logs"),
    dayNotes: table("day_notes"),
    checkins: table("checkins"),

    // convenience: browse coaches for the marketplace
    async coaches() {
      return must(await sb.from("profiles").select("*").eq("role", "coach"));
    },

    // realtime subscribe helper (e.g. new offers for a trainee)
    subscribe(tableName, filter, cb) {
      const ch = sb.channel(`rt-${tableName}-${Math.random().toString(36).slice(2)}`)
        .on("postgres_changes",
            { event: "*", schema: "public", table: tableName, filter },
            payload => cb(payload))
        .subscribe();
      return () => sb.removeChannel(ch);
    }
  };

  console.log("FormTrace store (Supabase) ready.");
})();
