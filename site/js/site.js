// NexLauncher site: release info, downloads, update sign-ups and the changelog come from Supabase.
// The publishable key is meant to be public: the database only allows reading published releases and
// calling record_download / download_count / subscribe.
const SUPABASE_URL = "https://yrtrfuwykdxuppvlgprd.supabase.co";
const SUPABASE_KEY = "sb_publishable_OP2RkKhrNxHDP-9acI5ANg_W0ktIgwB";
const BUCKET_URL = `${SUPABASE_URL}/storage/v1/object/public/releases/`;
const REPO = "NiyonshutiDavid/NexLauncher";

// Shown straight away and kept if Supabase can't be reached.
const FALLBACK_RELEASES = [
  { version: "3.1.0", title: "Runs on macOS 14 and later, on Apple silicon and Intel", published_at: "2026-10-27T12:00:00Z",
    download_path: "NexLauncher-3.1.0.zip", size_bytes: 9379369, min_macos: "14.0",
    files: { arm64: { path: "NexLauncher-3.1.0-arm64.zip", size_bytes: 5422295 }, x86_64: { path: "NexLauncher-3.1.0-x86_64.zip", size_bytes: 5680550 } },
    summary: "NexLauncher now runs on macOS Sonoma, Sequoia and Tahoe, on any Mac with Apple silicon or an Intel processor.",
    changes: [
      { kind: "added", text: "Support for macOS 14 Sonoma and macOS 15 Sequoia, with the standard system look; macOS 26 keeps Liquid Glass." },
      { kind: "added", text: "Builds for Intel Macs as well as Apple silicon, with a separate download for each." },
      { kind: "changed", text: "Antigravity runs through its agy command-line tool, and Gemini CLI shows Google's replacement notice." },
      { kind: "changed", text: "Pop-ups and the full-screen layout match the normal window." },
      { kind: "fixed", text: "The back button and breadcrumbs now respond to clicks, and the Ask AI panel fits the window." },
    ] },
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
  api("releases?select=version,title,summary,changes,published_at,download_path,size_bytes,min_macos,files&order=published_at.desc");

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
const releases = new Map(FALLBACK_RELEASES.map((r) => [r.version, r]));
const hasChipBuilds = (r) => Boolean(r?.files?.arm64 && r?.files?.x86_64);

function showRelease(release) {
  const fileURL = BUCKET_URL + release.download_path;
  document.querySelectorAll("[data-download]").forEach((a) => {
    if (a.closest("[data-changelog]")) return;            // changelog buttons keep their own version
    a.href = fileURL; a.dataset.version = release.version;
  });
  document.querySelectorAll("[data-release-version]").forEach((el) => (el.textContent = `Version ${release.version}`));
  document.querySelectorAll("[data-release-date]").forEach((el) => (el.textContent = formatDate(release.published_at)));
  document.querySelectorAll("[data-release-size]").forEach((el) => (el.textContent = hasChipBuilds(release) ? "Apple silicon and Intel" : formatSize(release.size_bytes)));
  document.querySelectorAll("[data-release-macos]").forEach((el) => (el.textContent = `macOS ${String(release.min_macos ?? "14.0").replace(/\.0$/, "")} or later`));
}

// Counts the download, then fetches the chip's zip (or the universal one when arch is null).
async function startDownload(version, arch) {
  const release = releases.get(version);
  let path = (arch && release?.files?.[arch]?.path) || release?.download_path;
  try { path = await api("rpc/record_download", { method: "POST", body: { p_version: version, p_arch: arch } }); }
  catch { /* still download, just uncounted */ }
  if (path) window.location.href = BUCKET_URL + path;
}

// Chrome and Firefox name the GPU (an "Apple M…" chip means Apple silicon). Safari hides it, so no guess there.
function guessArch() {
  try {
    const gl = document.createElement("canvas").getContext("webgl");
    const info = gl && gl.getExtension("WEBGL_debug_renderer_info");
    const renderer = info ? gl.getParameter(info.UNMASKED_RENDERER_WEBGL) : "";
    if (/Apple M\d/i.test(renderer)) return "arm64";
    if (/Intel|AMD|Radeon|NVIDIA/i.test(renderer)) return "x86_64";
  } catch { /* no WebGL */ }
  return null;
}

let chooser;
function openChooser(version) {
  const release = releases.get(version);
  if (!chooser) {
    chooser = document.createElement("dialog");
    chooser.className = "chooser";
    chooser.setAttribute("aria-labelledby", "chooser-title");
    document.body.appendChild(chooser);
    chooser.addEventListener("click", (event) => { if (event.target === chooser) chooser.close(); });   // click outside
  }
  const guess = guessArch();
  const option = (arch, name, detail, icon) => `
    <button class="choice" data-arch="${arch}" type="button">
      <i class="ph ${icon}"></i>
      <span><strong>${name}</strong><span>${detail}, ${formatSize(release.files[arch].size_bytes)}</span></span>
      ${guess === arch ? '<em class="guess">Likely your Mac</em>' : ""}
    </button>`;
  chooser.innerHTML = `
    <button class="chooser-close" type="button" aria-label="Close"><i class="ph ph-x"></i></button>
    <h2 id="chooser-title">Which Mac do you have?</h2>
    <p class="muted">NexLauncher ${escapeHTML(version)} for macOS ${String(release.min_macos ?? "14.0").replace(/\.0$/, "")} or later.</p>
    <div class="choices">
      ${option("arm64", "Apple silicon", "M1 and later", "ph-cpu")}
      ${option("x86_64", "Intel", "Intel Core processors", "ph-desktop")}
    </div>
    <p class="hint"><i class="ph ph-info"></i>Not sure? Open the Apple menu, choose About This Mac and look for Chip (Apple silicon) or Processor (Intel).</p>
    <button class="universal" type="button">Or get the universal version (${formatSize(release.size_bytes)}), which runs on both.</button>`;
  chooser.querySelector(".chooser-close").addEventListener("click", () => chooser.close());
  chooser.querySelectorAll(".choice").forEach((b) => b.addEventListener("click", () => { chooser.close(); startDownload(version, b.dataset.arch); }));
  chooser.querySelector(".universal").addEventListener("click", () => { chooser.close(); startDownload(version, null); });
  chooser.showModal();
  (chooser.querySelector(`.choice[data-arch="${guess}"]`) || chooser.querySelector(".choice")).focus();
}

function bindDownloadButtons() {
  document.querySelectorAll("[data-download]:not([data-bound])").forEach((a) => {
    a.dataset.bound = "1";
    a.addEventListener("click", (event) => {
      event.preventDefault();
      const version = a.dataset.version;
      if (hasChipBuilds(releases.get(version))) openChooser(version);
      else startDownload(version, null);
    });
  });
}

async function setupDownloads() {
  if (!document.querySelector("[data-download]")) return;
  showRelease(FALLBACK_RELEASES[0]);
  bindDownloadButtons();
  fetchReleases()
    .then((list) => {
      list.forEach((r) => releases.set(r.version, r));
      const latest = list.find((r) => r.download_path);
      if (latest) showRelease(latest);
    })
    .catch(() => {});
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
    .then((list) => {
      list?.forEach((r) => releases.set(r.version, r));
      renderReleases(list?.length ? list : FALLBACK_RELEASES, container);
    })
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
