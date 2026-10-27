// NexLauncher site: release info, downloads, update sign-ups and the changelog come from Supabase.
// The publishable key is meant to be public: the database only allows reading published releases and
// calling record_download / download_count / subscribe.
const SUPABASE_URL = "https://yrtrfuwykdxuppvlgprd.supabase.co";
const SUPABASE_KEY = "sb_publishable_OP2RkKhrNxHDP-9acI5ANg_W0ktIgwB";
const BUCKET_URL = `${SUPABASE_URL}/storage/v1/object/public/releases/`;
const REPO = "NiyonshutiDavid/NexLauncher";

// Shown straight away and kept if Supabase can't be reached.
const FALLBACK_RELEASES = [
  { version: "3.0.0", title: "AI assistant, Flutter devices and tasks", published_at: "2026-10-27T06:00:00Z",
    download_path: "NexLauncher-3.0.0.zip", size_bytes: 5369149, min_macos: "26.0",
    summary: "Hand tasks to AI agents, launch simulators and keep tasks per project.",
    changes: [
      { kind: "added", text: "AI assistant: give tasks to Claude Code, Codex, Antigravity (agy) or Gemini CLI, and reply to continue the conversation." },
      { kind: "added", text: "Ask AI side panel on every project page." },
      { kind: "added", text: "iOS simulators and Android emulators for Flutter, with compact launch pop-overs." },
      { kind: "added", text: "Tasks per project, shown in a new Tasks widget and in the menu bar panel." },
      { kind: "added", text: "Project filters (type, framework, git, running, pinned, collections) and breadcrumbs." },
      { kind: "added", text: "More stacks: Python, Go, Rust, Rails, Laravel, .NET, Elixir, Swift, static sites and more." },
      { kind: "changed", text: "WhatsApp-style window: controls inside the floating sidebar and a fading header, the same in full screen." },
      { kind: "changed", text: "Pop-ups are drawn inside the window." },
      { kind: "fixed", text: "The menu bar panel showed nothing, and header buttons did not respond to clicks." },
    ] },
  { version: "2.0.0", title: "App Store-style redesign", published_at: "2026-10-26T18:00:00Z", download_path: null,
    summary: "A cleaner home, nested projects, a terminal and themes.",
    changes: [
      { kind: "changed", text: "App Store-style home with a greeting, tip cards and illustrations." },
      { kind: "added", text: "Collections and nested projects, with a Cards and Folders switch." },
      { kind: "added", text: "Embedded terminal in any project or folder." },
      { kind: "added", text: "Add a project: create a folder or clone a repository." },
      { kind: "added", text: "Themes from nexventures.net in light and dark, with profile and settings in the window." },
      { kind: "added", text: "Pinning, notifications, a welcome tour and an orange app icon." },
    ] },
  { version: "1.0.0", title: "First launch", published_at: "2026-10-26T10:00:00Z", download_path: null,
    summary: "Find every project in your folder and run it from one window.",
    changes: [
      { kind: "added", text: "Finds projects from their manifests and tags full-stack ones." },
      { kind: "added", text: "Run Frontend, Backend, Both, Flutter or Docker with live logs and ports." },
      { kind: "added", text: "Git panel: identity, stage, commit, pull, push, branches and history." },
      { kind: "added", text: "Menu bar item, launch at login, and Running Services and Quick Launch widgets." },
    ] },
];

async function api(path, { method = "GET", body } = {}) {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/${path}`, {
    method,
    headers: { apikey: SUPABASE_KEY, Authorization: `Bearer ${SUPABASE_KEY}`, "Content-Type": "application/json" },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  const data = text ? JSON.parse(text) : null;
  if (!res.ok) throw Object.assign(new Error(data?.message || res.statusText), { code: data?.code });
  return data;
}

const fetchReleases = () =>
  api("releases?select=version,title,summary,changes,published_at,download_path,size_bytes,min_macos&order=published_at.desc");

const formatDate = (iso) => new Date(iso).toLocaleDateString("en-GB", { day: "numeric", month: "long", year: "numeric" });
const formatSize = (bytes) => (bytes ? `${(bytes / 1e6).toFixed(1)} MB` : "");
const escapeHTML = (s) => s.replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);

/* ---------- Navigation ---------- */
function setupNav() {
  const toggle = document.querySelector(".nav-toggle");
  const links = document.querySelector(".nav-links");
  if (!toggle || !links) return;
  toggle.addEventListener("click", () => {
    const open = links.classList.toggle("open");
    toggle.setAttribute("aria-expanded", String(open));
  });
}

/* ---------- Reveal on scroll ---------- */
function setupReveal() {
  const items = document.querySelectorAll(".reveal");
  if (!("IntersectionObserver" in window)) { items.forEach((el) => el.classList.add("is-visible")); return; }
  const io = new IntersectionObserver((entries) => {
    for (const e of entries) if (e.isIntersecting) { e.target.classList.add("is-visible"); io.unobserve(e.target); }
  }, { threshold: 0.15, rootMargin: "0px 0px -40px 0px" });
  items.forEach((el) => io.observe(el));
}

/* ---------- Latest release + download ---------- */
function showRelease(release) {
  const fileURL = BUCKET_URL + release.download_path;
  document.querySelectorAll("[data-download]").forEach((a) => { a.href = fileURL; a.dataset.version = release.version; });
  document.querySelectorAll("[data-release-version]").forEach((el) => (el.textContent = `Version ${release.version}`));
  document.querySelectorAll("[data-release-date]").forEach((el) => (el.textContent = formatDate(release.published_at)));
  document.querySelectorAll("[data-release-size]").forEach((el) => (el.textContent = formatSize(release.size_bytes)));
  document.querySelectorAll("[data-release-macos]").forEach((el) => (el.textContent = `macOS ${release.min_macos ?? "26.0"} or later`));
}

async function setupDownloads() {
  const buttons = document.querySelectorAll("[data-download]");
  if (!buttons.length) return;
  showRelease(FALLBACK_RELEASES[0]);
  fetchReleases()
    .then((list) => { const latest = list.find((r) => r.download_path); if (latest) showRelease(latest); })
    .catch(() => {});
  buttons.forEach((a) =>
    a.addEventListener("click", async (event) => {
      event.preventDefault();
      a.setAttribute("aria-busy", "true");
      let path = a.href.replace(BUCKET_URL, "");
      try { path = await api("rpc/record_download", { method: "POST", body: { p_version: a.dataset.version } }); }
      catch { /* still download, just uncounted */ }
      a.removeAttribute("aria-busy");
      window.location.href = BUCKET_URL + path;
    })
  );
  const counters = document.querySelectorAll("[data-download-count]");
  if (counters.length) {
    api("rpc/download_count", { method: "POST", body: {} })
      .then((n) => { if (n > 0) counters.forEach((el) => { el.textContent = `${Number(n).toLocaleString("en-GB")} downloads`; el.hidden = false; }); })
      .catch(() => {});
  }
}

/* ---------- Update sign-up ---------- */
function setupSubscribe() {
  document.querySelectorAll("form[data-subscribe]").forEach((form) => {
    const input = form.querySelector("input[type=email]");
    const button = form.querySelector("button");
    const status = form.querySelector(".status");
    form.addEventListener("submit", async (event) => {
      event.preventDefault();
      status.className = "status";
      const email = input.value.trim();
      if (!input.checkValidity() || !email) {
        status.textContent = "Enter an email address like name@example.com.";
        status.classList.add("err");
        input.focus();
        return;
      }
      button.setAttribute("aria-busy", "true");
      status.textContent = "Saving…";
      try {
        await api("rpc/subscribe", { method: "POST", body: { p_email: email } });
        status.textContent = "Thanks. We'll email you when a new version is out.";
        status.classList.add("ok");
        form.reset();
      } catch (err) {
        status.textContent = err.code === "23514"
          ? "That email address doesn't look right."
          : "Couldn't save that right now. Please try again in a moment.";
        status.classList.add("err");
      } finally {
        button.removeAttribute("aria-busy");
      }
    });
  });
}

/* ---------- Changelog ---------- */
function renderReleases(list, container) {
  container.innerHTML = list.map((r) => `
    <article class="release reveal is-visible" id="v${escapeHTML(r.version)}">
      <div class="release-side">
        <span class="release-version">${escapeHTML(r.version)}</span>
        <time class="release-date" datetime="${escapeHTML(r.published_at)}">${formatDate(r.published_at)}</time>
      </div>
      <div class="release-body">
        <h2 style="font-size: clamp(1.5rem, 2.6vw, 2rem)">${escapeHTML(r.title)}</h2>
        ${r.summary ? `<p>${escapeHTML(r.summary)}</p>` : ""}
        <ul class="changes">
          ${(r.changes || []).map((c) => `<li><span class="kind kind-${escapeHTML(c.kind)}">${escapeHTML(c.kind[0].toUpperCase() + c.kind.slice(1))}</span><span>${escapeHTML(c.text)}</span></li>`).join("")}
        </ul>
        ${r.download_path ? `<a class="btn btn-ghost btn-sm" data-download href="${BUCKET_URL + escapeHTML(r.download_path)}" data-version="${escapeHTML(r.version)}"><i class="ph ph-download-simple"></i>Download ${escapeHTML(r.version)}</a>` : ""}
      </div>
    </article>`).join("");
}

function setupChangelog() {
  const container = document.querySelector("[data-changelog]");
  if (!container) return;
  fetchReleases()
    .then((list) => { if (list?.length) renderReleases(list, container); else renderReleases(FALLBACK_RELEASES, container); })
    .catch(() => renderReleases(FALLBACK_RELEASES, container))
    .finally(setupDownloads);
}

/* ---------- Contributors ---------- */
function setupContributors() {
  const box = document.querySelector("[data-contributors]");
  if (!box) return;
  fetch(`https://api.github.com/repos/${REPO}/contributors?per_page=24`)
    .then((r) => (r.ok ? r.json() : Promise.reject()))
    .then((people) => {
      if (!people.length) return;
      box.innerHTML = people.map((p) => `
        <a href="${escapeHTML(p.html_url)}" rel="noopener">
          <img src="${escapeHTML(p.avatar_url)}&s=64" alt="" width="32" height="32" loading="lazy">${escapeHTML(p.login)}
        </a>`).join("");
    })
    .catch(() => {});
}

document.addEventListener("DOMContentLoaded", () => {
  setupNav();
  setupReveal();
  if (document.querySelector("[data-changelog]")) setupChangelog(); else setupDownloads();
  setupSubscribe();
  setupContributors();
});
