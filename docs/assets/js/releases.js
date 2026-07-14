(() => {
  "use strict";

  const API_URL = "https://api.github.com/repos/intelfans/WinDeployStudio/releases?per_page=100";
  const CACHE_KEY = "wds-pages-release-cache-v2";
  const CACHE_TTL = 6 * 60 * 60 * 1000;
  const SNAPSHOT_PATH = "assets/data/releases-snapshot.json";
  const GITHUB_HOSTS = new Set([
    "github.com",
    "objects.githubusercontent.com",
    "release-assets.githubusercontent.com",
  ]);

  // The local API snapshot contains the complete public release bodies. This
  // compact list is used only when both the live API and snapshot are absent.
  const LAST_RESORT_RELEASES = [
    {
      id: "fallback-v1.1.2",
      tag_name: "v1.1.2",
      name: "WinDeploy Studio v1.1.2",
      published_at: "2026-07-01T14:52:36Z",
      prerelease: false,
      html_url: "https://github.com/intelfans/WinDeployStudio/releases/tag/v1.1.2",
      body: "## New Features\n\n- Clearer community image download logging for Tiny, LTSC, 123, and global download selections.\n\n## Improvements\n\n- More reliable disk enumeration and diagnostics.\n- Safer temporary drive-letter selection for Windows To Go.\n- A cleaner Image Center warning flow.\n\n## Fixes\n\n- Corrected removable-disk partition metadata and several update, installer, and translation issues.",
      assets: [
        {
          name: "WinDeployStudio_Setup_1.1.2.exe",
          size: 50234890,
          digest: "sha256:86a398aa321ad56f0b0cb24ddbc815601c087599ae126e2deabe99ea51fac452",
          browser_download_url: "https://github.com/intelfans/WinDeployStudio/releases/download/v1.1.2/WinDeployStudio_Setup_1.1.2.exe",
        },
      ],
    },
    {
      id: "fallback-v1.1.1",
      tag_name: "v1.1.1",
      name: "WinDeploy Studio v1.1.1",
      published_at: "2026-06-29T13:42:00Z",
      prerelease: false,
      html_url: "https://github.com/intelfans/WinDeployStudio/releases/tag/v1.1.1",
      body: "## Highlights\n\n- Added the source-classified Image Center and Enterprise & LTSC entries.\n- Added explicit suitability indicators and source disclaimers.\n- Improved Windows To Go EFI boot partition reliability.",
      assets: [{ name: "WinDeployStudio_Setup_1.1.1.exe", size: 50224141, digest: "sha256:3e38f54e54ca572c396ead841a1a1b4ea4614240021a2841c2d8a0a71f4ebdeb", browser_download_url: "https://github.com/intelfans/WinDeployStudio/releases/download/v1.1.1/WinDeployStudio_Setup_1.1.1.exe" }],
    },
    {
      id: "fallback-v1.1.0",
      tag_name: "v1.1.0",
      name: "WinDeploy Studio v1.1.0",
      published_at: "2026-06-28T12:46:23Z",
      prerelease: false,
      html_url: "https://github.com/intelfans/WinDeployStudio/releases/tag/v1.1.0",
      body: "## Highlights\n\n- Refined Image Center categories for official, community, and enterprise images.\n- Added advanced tool safety notices and improved the Windows To Go waiting experience.",
      assets: [{ name: "WinDeployStudio_Setup_1.1.0.exe", size: 50186648, digest: "sha256:5df0c8b659f09a4b2f3e8db008e87a00764f703df5238bab85c3670d5e0462f6", browser_download_url: "https://github.com/intelfans/WinDeployStudio/releases/download/v1.1.0/WinDeployStudio_Setup_1.1.0.exe" }],
    },
    {
      id: "fallback-v1.0.2",
      tag_name: "v1.0.2",
      name: "WinDeploy Studio v1.0.2",
      published_at: "2026-06-27T11:25:25Z",
      prerelease: false,
      html_url: "https://github.com/intelfans/WinDeployStudio/releases/tag/v1.0.2",
      body: "## Highlights\n\n- Added measurable Windows To Go progress metrics and removed unreliable ETA estimates.",
      assets: [{ name: "WinDeployStudio_Setup_1.0.2.exe", size: 50113236, digest: "sha256:ed809e617c2484ad2c31e808ed3518f6253845d1bb7c496dda2c40a5409f17ed", browser_download_url: "https://github.com/intelfans/WinDeployStudio/releases/download/v1.0.2/WinDeployStudio_Setup_1.0.2.exe" }],
    },
    {
      id: "fallback-v1.0.1",
      tag_name: "v1.0.1",
      name: "WinDeploy Studio v1.0.1",
      published_at: "2026-06-25T12:14:46Z",
      prerelease: false,
      html_url: "https://github.com/intelfans/WinDeployStudio/releases/tag/v1.0.1",
      body: "## Highlights\n\n- Added explicit China and Global Mirror selection with clearer download control.",
      assets: [{ name: "WinDeployStudio_Setup_1.0.1.exe", size: 50110717, digest: "sha256:60716648e24a6c9d15d96a6614e6bbfbc1ba64e76f6f60aecb00f91e567f3e4b", browser_download_url: "https://github.com/intelfans/WinDeployStudio/releases/download/v1.0.1/WinDeployStudio_Setup_1.0.1.exe" }],
    },
    {
      id: "fallback-v1.0.0",
      tag_name: "v1.0.0",
      name: "WinDeploy Studio v1.0.0",
      published_at: "2026-06-24T05:18:21Z",
      prerelease: false,
      html_url: "https://github.com/intelfans/WinDeployStudio/releases/tag/v1.0.0",
      body: "## First public release\n\n- Windows To Go, bootable media creation, Image Center, Toolbox, AI Assistant, Log Center, and 11 interface languages.",
      assets: [{ name: "WinDeployStudio_Setup_1.0.0.0.exe", size: 50109161, digest: "sha256:6e4bda4b564a1d32192c943de60d14e375dc33bdb0d99ab8ba2717c0626c00df", browser_download_url: "https://github.com/intelfans/WinDeployStudio/releases/download/v1.0.0/WinDeployStudio_Setup_1.0.0.0.exe" }],
    },
  ];

  let releases = null;

  const element = (tag, className, text) => {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (text !== undefined) node.textContent = text;
    return node;
  };

  function t(key, values) {
    return window.WDS?.t(key, values) || key;
  }

  function readCache() {
    try {
      const cached = JSON.parse(localStorage.getItem(CACHE_KEY) || "null");
      if (!cached || !Array.isArray(cached.releases) || !cached.storedAt) return null;
      return cached;
    } catch (_) {
      return null;
    }
  }

  function writeCache(next) {
    try {
      localStorage.setItem(CACHE_KEY, JSON.stringify(next));
    } catch (_) {
      // Browsing remains functional when storage is unavailable.
    }
  }

  async function loadReleases() {
    const cached = readCache();
    if (cached && Date.now() - cached.storedAt < CACHE_TTL) return cached.releases;

    try {
      const headers = { Accept: "application/vnd.github+json" };
      if (cached?.etag) headers["If-None-Match"] = cached.etag;
      const response = await fetch(API_URL, { headers });
      if (response.status === 304 && cached) {
        cached.storedAt = Date.now();
        writeCache(cached);
        return cached.releases;
      }
      if (!response.ok) throw new Error(`GitHub Releases returned ${response.status}`);
      const body = await response.json();
      if (!Array.isArray(body)) throw new Error("GitHub Releases returned an unexpected response.");
      const visible = body.filter((release) => release && release.draft !== true);
      writeCache({
        storedAt: Date.now(),
        etag: response.headers.get("etag") || "",
        releases: visible,
      });
      return visible;
    } catch (apiError) {
      const root = window.WDS?.getRoot?.() || "./";
      const response = await fetch(`${root}${SNAPSHOT_PATH}`, { cache: "no-cache" });
      if (!response.ok) throw apiError;
      const snapshot = await response.json();
      if (!Array.isArray(snapshot)) throw apiError;
      return snapshot.filter((release) => release && release.draft !== true);
    }
  }

  function numericVersion(tagName) {
    const match = String(tagName || "").match(/v?(\d+)\.(\d+)\.(\d+)/i);
    return match ? [Number(match[1]), Number(match[2]), Number(match[3])] : [0, 0, 0];
  }

  function compareRelease(left, right) {
    const leftVersion = numericVersion(left.tag_name);
    const rightVersion = numericVersion(right.tag_name);
    for (let index = 0; index < 3; index += 1) {
      if (leftVersion[index] !== rightVersion[index]) return rightVersion[index] - leftVersion[index];
    }
    return new Date(right.published_at || 0) - new Date(left.published_at || 0);
  }

  function isStable(release) {
    const text = `${release.tag_name || ""} ${release.name || ""}`.toLowerCase();
    return release.prerelease !== true && !/(?:^|[^a-z0-9])(nightly|daily|dev|canary)(?:[^a-z0-9]|$)/.test(text);
  }

  function bestInstaller(release) {
    const exeAssets = (release.assets || []).filter((asset) => /\.exe$/i.test(asset?.name || "") && Number(asset.size || 0) > 0);
    const ranked = exeAssets.sort((left, right) => {
      const leftSetup = /(setup|install)/i.test(left.name || "") ? 1 : 0;
      const rightSetup = /(setup|install)/i.test(right.name || "") ? 1 : 0;
      if (leftSetup !== rightSetup) return rightSetup - leftSetup;
      return Number(right.size || 0) - Number(left.size || 0);
    });
    return ranked[0] || null;
  }

  function safeGitHubUrl(value) {
    try {
      const url = new URL(value);
      return url.protocol === "https:" && GITHUB_HOSTS.has(url.host) ? url.href : "";
    } catch (_) {
      return "";
    }
  }

  function formatBytes(bytes) {
    const value = Number(bytes || 0);
    if (!value) return "--";
    return `${(value / (1024 * 1024)).toFixed(1)} MB`;
  }

  function formatDate(value) {
    const date = new Date(value || 0);
    if (Number.isNaN(date.getTime())) return "--";
    return new Intl.DateTimeFormat(window.WDS?.getLanguage() === "en" ? "en-US" : "zh-CN", {
      year: "numeric",
      month: "short",
      day: "numeric",
    }).format(date);
  }

  function sha256(asset) {
    const match = String(asset?.digest || "").match(/^sha256:([a-f0-9]{64})$/i);
    return match ? match[1].toUpperCase() : "--";
  }

  function selectReleaseNotes(body) {
    const content = String(body || "").trim();
    if (!content) return content;

    const language = window.WDS?.getLanguage?.() === "en" ? "en" : "zh";
    const markedSections = {};
    const marker = /<!--\s*wds:lang=(zh|en)\s*-->\s*([\s\S]*?)(?=<!--\s*wds:lang=(?:zh|en)\s*-->|$)/gi;
    let match = marker.exec(content);
    while (match) {
      markedSections[match[1].toLowerCase()] = match[2].trim();
      match = marker.exec(content);
    }
    if (markedSections[language]) return markedSections[language];

    const sections = content
      .split(/^\s{0,3}(?:-{3,}|\*{3,}|_{3,})\s*$/m)
      .map((section) => section.trim())
      .filter(Boolean);
    if (sections.length < 2) return content;

    const cjkCount = (section) => (section.match(/[\u3400-\u9FFF\uF900-\uFAFF]/g) || []).length;
    const chinese = sections.find((section) => cjkCount(section) > 0);
    const english = sections.find((section) => cjkCount(section) === 0);
    return language === "zh" ? chinese || content : english || content;
  }

  // Historical GitHub release bodies mention the retired provider. Keep the
  // site current even when notes come from a user's existing cache.
  function sanitizeLegacyMirrorNames(body) {
    const replacement = window.WDS?.getLanguage?.() === "en" ? "global download" : "国际下载";
    return String(body || "")
      .replace(/\bGoFile\b/gi, replacement)
      .replace(/\bSourceForge\b(?!\.net)/gi, "Global Mirror");
  }

  function markdown(body) {
    const container = element("div", "markdown-body");
    const content = String(body || "").trim();
    if (!content) {
      container.textContent = t("release_no_notes");
      return container;
    }
    if (window.marked?.parse && window.DOMPurify?.sanitize) {
      container.innerHTML = window.DOMPurify.sanitize(window.marked.parse(content), {
        USE_PROFILES: { html: true },
      });
      container.querySelectorAll("a").forEach((link) => {
        link.target = "_blank";
        link.rel = "noreferrer";
      });
    } else {
      container.textContent = content;
    }
    return container;
  }

  function releaseLink(release) {
    return safeGitHubUrl(release.html_url) || `https://github.com/intelfans/WinDeployStudio/releases/tag/${encodeURIComponent(release.tag_name || "")}`;
  }

  function actionLink(label, href, primary = false) {
    const anchor = element("a", `button ${primary ? "button-primary" : "button-secondary"}`, label);
    anchor.href = href;
    anchor.target = "_blank";
    anchor.rel = "noreferrer";
    return anchor;
  }

  function metadataGrid(release, asset) {
    const meta = element("dl", "dialog-grid");
    const values = [
      [t("release_published"), formatDate(release.published_at)],
      [t("release_size"), asset ? formatBytes(asset.size) : "--"],
      [t("release_file"), asset?.name || t("release_asset_unavailable")],
    ];
    if (asset) values.push([t("release_sha256"), sha256(asset)]);
    values.forEach(([label, value]) => {
      const item = element("div");
      item.append(element("dt", "", label), element("dd", "", value));
      meta.append(item);
    });
    return meta;
  }

  function sourceOptions(release, asset) {
    const sources = element("div", "download-sources");
    const globalMirror = element("div", "source-option");
    const globalMirrorCopy = element("div");
    globalMirrorCopy.append(element("h4", "", t("release_global_mirror")), element("p", "", t("release_global_mirror_copy")));
    const pending = element("button", "button button-secondary", t("release_global_mirror_pending"));
    pending.type = "button";
    pending.disabled = true;
    globalMirror.append(globalMirrorCopy, pending);

    const github = element("div", "source-option");
    const githubCopy = element("div");
    githubCopy.append(element("h4", "", "GitHub Releases"), element("p", "", t("release_github_copy")));
    if (asset && safeGitHubUrl(asset.browser_download_url)) {
      github.append(githubCopy, actionLink(t("release_download_github"), safeGitHubUrl(asset.browser_download_url), true));
    } else {
      const unavailable = element("button", "button button-secondary", t("release_asset_unavailable"));
      unavailable.disabled = true;
      github.append(githubCopy, unavailable);
    }
    sources.append(globalMirror, github);
    return sources;
  }

  function latestPanel(release) {
    const asset = bestInstaller(release);
    const panel = element("div");
    const heading = element("div", "release-heading");
    const headingCopy = element("div");
    headingCopy.append(element("h3", "", release.name || release.tag_name || "WinDeploy Studio"));
    const meta = element("p", "release-meta");
    meta.append(
      element("span", "", release.tag_name || "--"),
      element("span", "", `${t("release_published")}: ${formatDate(release.published_at)}`),
    );
    headingCopy.append(meta);
    const actions = element("div", "release-actions");
    actions.append(actionLink(t("release_open_github"), releaseLink(release)));
    heading.append(headingCopy, actions);
    panel.append(heading, metadataGrid(release, asset), sourceOptions(release, asset));
    const notes = element("section", "release-notes");
    notes.append(element("h3", "", t("release_notes")), markdown(sanitizeLegacyMirrorNames(selectReleaseNotes(release.body))));
    panel.append(notes);
    return panel;
  }

  function historyRecord(release) {
    const asset = bestInstaller(release);
    const record = element("details", "release-record");
    const summary = element("summary");
    const title = element("div");
    title.append(element("strong", "", release.name || release.tag_name || "WinDeploy Studio"));
    const meta = element("p", "release-meta");
    meta.append(element("span", "", release.tag_name || "--"), element("span", "", formatDate(release.published_at)));
    title.append(meta);
    summary.append(title);
    const content = element("div", "release-record-content");
    content.append(metadataGrid(release, asset));
    const notes = element("section", "release-notes");
    notes.append(element("h3", "", t("release_notes")), markdown(sanitizeLegacyMirrorNames(selectReleaseNotes(release.body))));
    content.append(notes);
    const actions = element("div", "release-actions");
    actions.append(actionLink(t("release_open_github"), releaseLink(release)));
    if (asset && safeGitHubUrl(asset.browser_download_url)) {
      actions.append(actionLink(t("release_download_github"), safeGitHubUrl(asset.browser_download_url), true));
    }
    content.append(actions);
    record.append(summary, content);
    return record;
  }

  function updateHomeVersion(list) {
    const slot = document.querySelector("#home-release-version");
    if (!slot) return;
    const stable = list.filter(isStable).sort(compareRelease)[0] || list.sort(compareRelease)[0];
    slot.textContent = stable?.tag_name || "--";
  }

  function renderDownloads(list) {
    const latestSlot = document.querySelector("#latest-release");
    const historySlot = document.querySelector("#release-history");
    if (!latestSlot || !historySlot) return;
    const sorted = [...list].sort(compareRelease);
    const stable = sorted.filter(isStable);
    const latest = stable[0] || sorted[0];
    latestSlot.replaceChildren(latest ? latestPanel(latest) : element("div", "empty-state", t("release_failed")));
    historySlot.replaceChildren();
    const history = sorted.filter((release) => release.id !== latest?.id);
    if (!history.length) {
      historySlot.append(element("div", "empty-state", t("release_no_notes")));
      return;
    }
    history.forEach((release) => historySlot.append(historyRecord(release)));
  }

  function renderError() {
    const latestSlot = document.querySelector("#latest-release");
    const historySlot = document.querySelector("#release-history");
    const homeVersion = document.querySelector("#home-release-version");
    if (homeVersion) homeVersion.textContent = "--";
    if (latestSlot) {
      const error = element("div", "release-error");
      error.append(element("span", "", t("release_failed")), actionLink(t("release_open_github"), "https://github.com/intelfans/WinDeployStudio/releases"));
      latestSlot.replaceChildren(error);
    }
    if (historySlot) historySlot.replaceChildren(element("div", "empty-state", t("release_failed")));
  }

  async function render() {
    try {
      releases = await loadReleases();
      updateHomeVersion(releases);
      renderDownloads(releases);
      window.WDS?.refreshIcons();
    } catch (error) {
      console.warn("Could not load GitHub Releases", error);
      releases = LAST_RESORT_RELEASES;
      updateHomeVersion(releases);
      renderDownloads(releases);
      window.WDS?.refreshIcons();
    }
  }

  document.addEventListener("DOMContentLoaded", render);
  document.addEventListener("wds:languagechange", () => {
    if (releases) {
      updateHomeVersion(releases);
      renderDownloads(releases);
      window.WDS?.refreshIcons();
    }
  });
})();
