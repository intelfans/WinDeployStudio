(() => {
  "use strict";

  const catalog = [
    {
      id: "official-win10",
      group: "official",
      level: "beginner",
      source: "official",
      name: { zh: "官方 Windows 10", en: "Official Windows 10" },
      version: "Windows 10 22H2",
      architecture: "x64",
      size: "--",
      copy: { zh: "来自 Microsoft 的标准安装镜像入口。", en: "Standard installation image entry from Microsoft." },
      workflows: ["install", "togo"],
      caution: { zh: "使用官方来源下载，并在部署前核对版本与许可。", en: "Use the official source and verify version and licensing before deployment." },
    },
    {
      id: "official-win11",
      group: "official",
      level: "beginner",
      source: "official",
      name: { zh: "官方 Windows 11", en: "Official Windows 11" },
      version: "Windows 11 25H2",
      architecture: "x64",
      size: "--",
      copy: { zh: "来自 Microsoft 的标准安装镜像入口。", en: "Standard installation image entry from Microsoft." },
      workflows: ["install", "togo"],
      caution: { zh: "使用官方来源下载，并在部署前核对版本与许可。", en: "Use the official source and verify version and licensing before deployment." },
    },
    {
      id: "tiny10",
      group: "community",
      level: "advanced",
      source: "community",
      name: { zh: "Tiny10", en: "Tiny10" },
      version: "Windows 10 22H2",
      architecture: "x64",
      size: "3.58 GB",
      copy: { zh: "面向低配置设备、虚拟机与测试环境的社区精简系统。", en: "A lightweight community build for low-end devices, VMs, and testing." },
      workflows: ["install"],
      caution: { zh: "第三方修改镜像。使用前请确认来源、完整性、授权与兼容性。", en: "Third-party modified image. Verify source, integrity, licensing, and compatibility before use." },
    },
    {
      id: "tiny11",
      group: "community",
      level: "advanced",
      source: "community",
      name: { zh: "Tiny11", en: "Tiny11" },
      version: "Windows 11 25H2",
      architecture: "x64",
      size: "--",
      copy: { zh: "适合测试用途的社区精简 Windows 11 选项。", en: "A community lightweight Windows 11 option for testing use cases." },
      workflows: ["install"],
      caution: { zh: "第三方修改镜像。使用前请确认来源、完整性、授权与兼容性。", en: "Third-party modified image. Verify source, integrity, licensing, and compatibility before use." },
    },
    {
      id: "xlite10",
      group: "community",
      level: "advanced",
      source: "community",
      name: { zh: "Windows X-Lite 10", en: "Windows X-Lite 10" },
      version: "Windows 10",
      architecture: "x64",
      size: "--",
      copy: { zh: "以较低资源占用为目标的社区版本。", en: "A community edition focused on lower resource use." },
      workflows: ["install"],
      caution: { zh: "第三方修改镜像。仅在了解组件变更与许可限制后使用。", en: "Third-party modified image. Use only after reviewing component changes and licensing limits." },
    },
    {
      id: "xlite11",
      group: "community",
      level: "advanced",
      source: "community",
      name: { zh: "Windows X-Lite 11", en: "Windows X-Lite 11" },
      version: "Windows 11",
      architecture: "x64",
      size: "--",
      copy: { zh: "以较低资源占用为目标的社区版本。", en: "A community edition focused on lower resource use." },
      workflows: ["install"],
      caution: { zh: "第三方修改镜像。仅在了解组件变更与许可限制后使用。", en: "Third-party modified image. Use only after reviewing component changes and licensing limits." },
    },
    {
      id: "starvalleyx",
      group: "community",
      level: "advanced",
      source: "community",
      chineseOnly: true,
      name: { zh: "StarValleyX", en: "StarValleyX" },
      version: "Windows 10",
      architecture: "x64",
      size: "--",
      copy: { zh: "面向中文用户的社区镜像资源。", en: "A community image resource intended for Chinese-language users." },
      workflows: ["install"],
      caution: { zh: "第三方修改镜像。使用前请独立核验开发者来源、许可与文件哈希。", en: "Third-party modified image. Independently verify developer source, license, and file hash before use." },
    },
    {
      id: "ltsc-win10-enterprise",
      group: "enterprise",
      level: "expert",
      source: "community",
      name: { zh: "Windows 10 企业版 LTSC", en: "Windows 10 Enterprise LTSC" },
      version: "Windows 10 Enterprise LTSC",
      architecture: "x64",
      size: "--",
      copy: { zh: "面向专业部署场景的企业长期服务版本。", en: "Enterprise long-term servicing edition for professional deployment scenarios." },
      workflows: ["install", "togo"],
      caution: { zh: "专家级资源。请确认组织许可、更新策略与部署要求。", en: "Expert-level resource. Confirm organizational licensing, update policy, and deployment requirements." },
    },
    {
      id: "ltsc-win11-enterprise",
      group: "enterprise",
      level: "expert",
      source: "community",
      name: { zh: "Windows 11 企业版 LTSC", en: "Windows 11 Enterprise LTSC" },
      version: "Windows 11 Enterprise LTSC",
      architecture: "x64",
      size: "--",
      copy: { zh: "面向专业部署场景的企业长期服务版本。", en: "Enterprise long-term servicing edition for professional deployment scenarios." },
      workflows: ["install", "togo"],
      caution: { zh: "专家级资源。请确认组织许可、更新策略与部署要求。", en: "Expert-level resource. Confirm organizational licensing, update policy, and deployment requirements." },
    },
    {
      id: "ltsc-win10-iot",
      group: "enterprise",
      level: "expert",
      source: "community",
      name: { zh: "Windows 10 IoT 企业版 LTSC", en: "Windows 10 IoT Enterprise LTSC" },
      version: "Windows 10 IoT Enterprise LTSC",
      architecture: "x64",
      size: "--",
      copy: { zh: "面向嵌入式与专业设备部署场景。", en: "For embedded and professional device deployment scenarios." },
      workflows: ["install"],
      caution: { zh: "专家级资源。请确认设备适配、许可与使用范围。", en: "Expert-level resource. Confirm device suitability, licensing, and allowed use." },
    },
    {
      id: "ltsc-win11-iot",
      group: "enterprise",
      level: "expert",
      source: "community",
      name: { zh: "Windows 11 IoT 企业版 LTSC", en: "Windows 11 IoT Enterprise LTSC" },
      version: "Windows 11 IoT Enterprise LTSC",
      architecture: "x64",
      size: "--",
      copy: { zh: "面向嵌入式与专业设备部署场景。", en: "For embedded and professional device deployment scenarios." },
      workflows: ["install"],
      caution: { zh: "专家级资源。请确认设备适配、许可与使用范围。", en: "Expert-level resource. Confirm device suitability, licensing, and allowed use." },
    },
    {
      id: "font-pack",
      group: "tools",
      level: "beginner",
      source: "release",
      chineseOnly: true,
      name: { zh: "CJK 字体包", en: "CJK Font Pack" },
      version: "Supplementary package",
      architecture: "Windows 10 / 11",
      size: "--",
      copy: { zh: "为 Tiny10、Tiny11 与 Windows X-Lite 补充 CJK 文本显示。", en: "Supplementary CJK text rendering for Tiny10, Tiny11, and Windows X-Lite." },
      workflows: ["install"],
      caution: { zh: "仅应发布具备再分发许可的字体文件。", en: "Only fonts with confirmed redistribution rights should be published." },
    },
  ];

  const filters = ["all", "official", "community", "enterprise", "tools"];
  let activeFilter = "all";
  let activeImageId = null;

  const node = (tag, className, text) => {
    const element = document.createElement(tag);
    if (className) element.className = className;
    if (text !== undefined) element.textContent = text;
    return element;
  };

  const t = (key, values) => window.WDS?.t(key, values) || key;
  const language = () => window.WDS?.getLanguage() || "zh";
  const localized = (value) => value?.[language()] || value?.zh || value?.en || "";

  function categoryLabel(group) {
    return t(`category_${group}`);
  }

  function sourceLabel(source) {
    return t(`source_${source}`);
  }

  function levelLabel(level) {
    return t(`level_${level}`);
  }

  function workflowLabel(workflow) {
    return t(`workflow_${workflow}`);
  }

  function availableItems() {
    return catalog.filter((item) => !item.chineseOnly || language() === "zh");
  }

  function filteredItems() {
    return availableItems().filter((item) => activeFilter === "all" || item.group === activeFilter);
  }

  function renderFilters() {
    const root = document.querySelector("#image-filters");
    if (!root) return;
    root.replaceChildren();
    filters.forEach((filter) => {
      const button = node("button", "filter-button", t(`filter_${filter}`));
      button.type = "button";
      button.dataset.filter = filter;
      button.setAttribute("aria-pressed", String(filter === activeFilter));
      button.addEventListener("click", () => {
        activeFilter = filter;
        renderFilters();
        renderCatalog();
      });
      root.append(button);
    });
  }

  function renderCatalog() {
    const root = document.querySelector("#image-catalog");
    if (!root) return;
    root.replaceChildren();
    const items = filteredItems();
    if (!items.length) {
      root.append(node("div", "empty-state", t("image_placeholder_copy")));
      return;
    }
    items.forEach((item) => {
      const card = node("article", "image-card");
      const top = node("div", "image-card-topline");
      top.append(
        node("span", "source-label", sourceLabel(item.source)),
        (() => {
          const label = node("span", "level-label", levelLabel(item.level));
          label.dataset.level = item.level;
          return label;
        })(),
      );
      const title = node("h3", "", localized(item.name));
      const copy = node("p", "", localized(item.copy));
      const facts = node("p", "image-facts");
      facts.append(
        node("span", "", item.version),
        node("span", "", item.architecture),
        node("span", "", item.size),
      );
      const action = node("button", "button button-secondary", t("image_view"));
      action.type = "button";
      action.addEventListener("click", () => openItem(item.id));
      card.append(top, title, copy, facts, action);
      root.append(card);
    });
  }

  function makeFact(label, value) {
    const item = node("div");
    item.append(node("dt", "", label), node("dd", "", value));
    return item;
  }

  function placeholderSource() {
    const source = node("div", "source-option");
    const copy = node("div");
    copy.append(node("h4", "", t("release_sourceforge")), node("p", "", t("image_placeholder_copy")));
    const pending = node("button", "button button-secondary", t("release_sourceforge_pending"));
    pending.type = "button";
    pending.disabled = true;
    source.append(copy, pending);
    return source;
  }

  function openItem(id) {
    const item = catalog.find((candidate) => candidate.id === id);
    const dialog = document.querySelector("#image-dialog");
    if (!item || !dialog) return;
    activeImageId = id;
    document.querySelector("#image-dialog-category").textContent = categoryLabel(item.group);
    document.querySelector("#image-dialog-title").textContent = localized(item.name);
    const content = document.querySelector("#image-dialog-content");
    content.replaceChildren();
    const body = node("div", "dialog-content");
    body.append(node("p", "", localized(item.copy)));
    const facts = node("dl", "dialog-grid");
    facts.append(
      makeFact(t("image_source"), sourceLabel(item.source)),
      makeFact(t("image_level"), levelLabel(item.level)),
      makeFact(t("image_architecture"), item.architecture),
      makeFact(t("image_size"), item.size),
      makeFact(t("image_workflows"), item.workflows.map(workflowLabel).join(" · ")),
      makeFact(t("image_version"), item.version),
    );
    body.append(facts);
    body.append(node("div", "notice", localized(item.caution)));
    body.append(node("h3", "", t("image_download_sources")));
    const sources = node("div", "download-sources");
    sources.append(placeholderSource());
    body.append(sources);
    content.append(body);
    if (!dialog.open) dialog.showModal();
    const url = new URL(window.location.href);
    url.searchParams.set("image", id);
    window.history.replaceState({}, "", url);
    window.WDS?.refreshIcons();
  }

  function closeDialog() {
    const dialog = document.querySelector("#image-dialog");
    if (!dialog?.open) return;
    dialog.close();
    activeImageId = null;
    const url = new URL(window.location.href);
    url.searchParams.delete("image");
    window.history.replaceState({}, "", url);
  }

  function setupDialog() {
    const dialog = document.querySelector("#image-dialog");
    if (!dialog) return;
    document.querySelector("[data-dialog-close]")?.addEventListener("click", closeDialog);
    dialog.addEventListener("click", (event) => {
      if (event.target === dialog) closeDialog();
    });
    dialog.addEventListener("cancel", () => {
      activeImageId = null;
      const url = new URL(window.location.href);
      url.searchParams.delete("image");
      window.history.replaceState({}, "", url);
    });
  }

  function render() {
    renderFilters();
    renderCatalog();
    const requested = new URLSearchParams(window.location.search).get("image");
    if (requested && availableItems().some((item) => item.id === requested)) {
      openItem(requested);
    } else if (activeImageId) {
      const current = availableItems().find((item) => item.id === activeImageId);
      if (current) openItem(current.id);
    }
  }

  document.addEventListener("DOMContentLoaded", () => {
    setupDialog();
    render();
  });
  document.addEventListener("wds:languagechange", render);
})();
