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
      officialLink: {
        zh: "https://www.microsoft.com/zh-cn/software-download/windows10",
        en: "https://www.microsoft.com/zh-cn/software-download/windows10",
      },
      chinaLink: "https://1842249449.share.123pan.cn/123pan/Z4L0Td-KMR0h",
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
      officialLink: {
        zh: "https://www.microsoft.com/zh-cn/software-download/windows11",
        en: "https://www.microsoft.com/en-us/software-download/windows11",
      },
      chinaLink: "https://1842249449.share.123pan.cn/123pan/Z4L0Td-FjXKh",
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
      chinaLink: "https://1842249449.share.123pan.cn/123pan/Z4L0Td-NRSKh",
      internationalLink: "https://downloads.sourceforge.net/project/windeploystudio/Extended%20Files/TinyOS/Tiny10_22H2.iso",
      checksums: {
        sha256: "a11116c0645d892d6a5a7c585ecc1fa13aa66f8c7cc6b03bf1f27bd16860cc35",
        md5: "893f0df3bb42f3a4d63ed3632ac47d59",
      },
      caution: { zh: "第三方修改镜像，仅提供英文版。首次启动后请手动切换系统语言和时区，并安装 CJK 字体包以正确显示中日韩文字。使用前请确认来源、完整性、授权与兼容性。", en: "Third-party modified image. Verify source, integrity, licensing, and compatibility before use." },
    },
    {
      id: "tiny11",
      group: "community",
      level: "advanced",
      source: "community",
      name: { zh: "Tiny11", en: "Tiny11" },
      version: "Windows 11 25H2",
      architecture: "x64",
      size: "5.14 GB",
      copy: { zh: "适合测试用途的社区精简 Windows 11 选项。", en: "A community lightweight Windows 11 option for testing use cases." },
      workflows: ["install"],
      chinaLink: "https://1842249449.share.123pan.cn/123pan/Z4L0Td-uMR0h",
      internationalLink: "https://downloads.sourceforge.net/project/windeploystudio/Extended%20Files/TinyOS/Tiny11_25H2.iso",
      checksums: {
        sha256: "92484f2b7f707e42383294402a9eabbadeaa5ede80ac633390ae7f3537e36275",
        md5: "6c0eca7293783aac080e9f8717c4dcb7",
      },
      caution: { zh: "第三方修改镜像，仅提供英文版。首次启动后请手动切换系统语言和时区，并安装 CJK 字体包以正确显示中日韩文字。使用前请确认来源、完整性、授权与兼容性。", en: "Third-party modified image. Verify source, integrity, licensing, and compatibility before use." },
    },
    {
      id: "xlite10",
      group: "community",
      level: "advanced",
      source: "community",
      name: { zh: "Windows X-Lite 10", en: "Windows X-Lite 10" },
      version: "Windows 10",
      architecture: "x64",
      size: "3.78 GB",
      copy: { zh: "以较低资源占用为目标的社区版本。", en: "A community edition focused on lower resource use." },
      workflows: ["install"],
      chinaLink: "https://1842249449.share.123pan.cn/123pan/Z4L0Td-1ZRKh",
      internationalLink: "https://downloads.sourceforge.net/project/windeploystudio/Extended%20Files/Windows%20X-Lite/WindowsX-Lite_10.iso",
      checksums: {
        sha256: "d2e47d6a91d5ef3441e69ba25f363d50317940b4cc91c2fd5f5ed1b1ebfd6d2c",
        md5: "f2bd1ebb4d782a98ff5aafda36357efb",
      },
      caution: { zh: "第三方修改镜像，仅提供英文版。首次启动后请手动切换系统语言和时区，并安装 CJK 字体包以正确显示中日韩文字。仅在了解组件变更与许可限制后使用。", en: "Third-party modified image. Use only after reviewing component changes and licensing limits." },
    },
    {
      id: "xlite11",
      group: "community",
      level: "advanced",
      source: "community",
      name: { zh: "Windows X-Lite 11", en: "Windows X-Lite 11" },
      version: "Windows 11",
      architecture: "x64",
      size: "3.67 GB",
      copy: { zh: "以较低资源占用为目标的社区版本。", en: "A community edition focused on lower resource use." },
      workflows: ["install"],
      chinaLink: "https://1842249449.share.123pan.cn/123pan/Z4L0Td-UMR0h",
      internationalLink: "https://downloads.sourceforge.net/project/windeploystudio/Extended%20Files/Windows%20X-Lite/WindowsX-Lite_11.iso",
      checksums: {
        sha256: "1656aad50bc882de828585113e9231a951ce76b6baf3cd77709430cb35da5a7f",
        md5: "2b56980fe97484b5d0a23129148a0c77",
      },
      caution: { zh: "第三方修改镜像，仅提供英文版。首次启动后请手动切换系统语言和时区，并安装 CJK 字体包以正确显示中日韩文字。仅在了解组件变更与许可限制后使用。", en: "Third-party modified image. Use only after reviewing component changes and licensing limits." },
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
      size: "9.64 GB",
      copy: { zh: "面向中文用户的社区镜像资源。", en: "A community image resource intended for Chinese-language users." },
      workflows: ["install"],
      chinaLink: "https://1842249449.share.123pan.cn/123pan/Z4L0Td-Vyt0h",
      showInternationalDownload: false,
      checksums: {
        sha256: "c47c30b2fc4dcdaf01944631866aed7e9c740aaacd079e57ea939c64b4cf0350",
        md5: "6a13ccb0cd594d1f955cdd2d676edd54",
      },
      caution: { zh: "第三方修改镜像。使用前请独立核验开发者来源、许可、SHA-256 与 MD5。", en: "Third-party modified image. Independently verify developer source, license, SHA-256, and MD5 before use." },
    },
    {
      id: "ltsc-win10-enterprise",
      group: "enterprise",
      level: "expert",
      source: "community",
      name: { zh: "Windows 10 企业版 LTSC", en: "Windows 10 Enterprise LTSC" },
      version: "Windows 10 Enterprise LTSC",
      architecture: "x64",
      size: { zh: "4.70 GB", en: "4.56 GB" },
      copy: { zh: "面向专业部署场景的企业长期服务版本。", en: "Enterprise long-term servicing edition for professional deployment scenarios." },
      workflows: ["install", "togo"],
      chinaLink: "https://1842249449.share.123pan.cn/123pan/Z4L0Td-WkS0h",
      internationalLink: "https://downloads.sourceforge.net/project/windeploystudio/Extended%20Files/LTSC/Enterprise/Windows%2010%20Enterprise%20LTSC.iso",
      checksums: {
        sha256: "c90a6df8997bf49e56b9673982f3e80745058723a707aef8f22998ae6479597d",
        md5: "b5a7be560dbd73619945129e52be1b5f",
        nonChineseOnly: true,
      },
      caution: { zh: "专家级资源。请确认组织许可、更新策略与部署要求。", en: "Expert-level resource. Confirm organizational licensing, update policy, and deployment requirements." },
      languageNotice: { zh: "LTSC 语言提示：123 云盘提供简体中文版本，国际渠道提供英文版本。", en: "LTSC language note: 123 Cloud provides the Simplified Chinese build; International Channel provides the English build." },
    },
    {
      id: "ltsc-win11-enterprise",
      group: "enterprise",
      level: "expert",
      source: "community",
      name: { zh: "Windows 11 企业版 LTSC", en: "Windows 11 Enterprise LTSC" },
      version: "Windows 11 Enterprise LTSC",
      architecture: "x64",
      size: { zh: "4.92 GB", en: "4.77 GB" },
      copy: { zh: "面向专业部署场景的企业长期服务版本。", en: "Enterprise long-term servicing edition for professional deployment scenarios." },
      workflows: ["install", "togo"],
      chinaLink: "https://1842249449.share.123pan.cn/123pan/Z4L0Td-3g4Kh",
      internationalLink: "https://downloads.sourceforge.net/project/windeploystudio/Extended%20Files/LTSC/Enterprise/Windows%2011%20Enterprise%20LTSC.iso",
      checksums: {
        sha256: "157d8365a517c40afeb3106fdd74d0836e1025debbc343f2080e1a8687607f51",
        md5: "60c6f86bf378892648cfb5524b9416e2",
        nonChineseOnly: true,
      },
      caution: { zh: "专家级资源。请确认组织许可、更新策略与部署要求。", en: "Expert-level resource. Confirm organizational licensing, update policy, and deployment requirements." },
      languageNotice: { zh: "LTSC 语言提示：123 云盘提供简体中文版本，国际渠道提供英文版本。", en: "LTSC language note: 123 Cloud provides the Simplified Chinese build; International Channel provides the English build." },
    },
    {
      id: "ltsc-win10-iot",
      group: "enterprise",
      level: "expert",
      source: "community",
      name: { zh: "Windows 10 IoT 企业版 LTSC", en: "Windows 10 IoT Enterprise LTSC" },
      version: "Windows 10 IoT Enterprise LTSC",
      architecture: "x64",
      size: "4.52 GB",
      copy: { zh: "面向嵌入式与专业设备部署场景。", en: "For embedded and professional device deployment scenarios." },
      workflows: ["install"],
      chinaLink: "https://1842249449.share.123pan.cn/123pan/Z4L0Td-dmMKh",
      internationalLink: "https://downloads.sourceforge.net/project/windeploystudio/Extended%20Files/LTSC/iot/Windows%2010%20iot%20LTSC.iso",
      checksums: {
        sha256: "a0334f31ea7a3e6932b9ad7206608248f0bd40698bfb8fc65f14fc5e4976c160",
        md5: "2463b19beac328290e6a8adcedb7533a",
      },
      caution: { zh: "专家级资源，仅提供英文版。首次启动后请手动切换系统语言和时区，并安装 CJK 字体包以正确显示中日韩文字。请确认设备适配、许可与使用范围。", en: "Expert-level resource. Confirm device suitability, licensing, and allowed use." },
      languageNotice: { zh: "IoT LTSC 语言提示：仅提供英文版；123 云盘和国际渠道均为英文版。", en: "IoT LTSC language note: only English builds are provided; both 123 Cloud and International Channel provide the English build." },
    },
    {
      id: "ltsc-win11-iot",
      group: "enterprise",
      level: "expert",
      source: "community",
      name: { zh: "Windows 11 IoT 企业版 LTSC", en: "Windows 11 IoT Enterprise LTSC" },
      version: "Windows 11 IoT Enterprise LTSC",
      architecture: "x64",
      size: "4.79 GB",
      copy: { zh: "面向嵌入式与专业设备部署场景。", en: "For embedded and professional device deployment scenarios." },
      workflows: ["install"],
      chinaLink: "https://1842249449.share.123pan.cn/123pan/Z4L0Td-aVt0h",
      internationalLink: "https://downloads.sourceforge.net/project/windeploystudio/Extended%20Files/LTSC/iot/Windows%2011%20iot%20LTSC.iso",
      checksums: {
        sha256: "4f59662a96fc1da48c1b415d6c369d08af55ddd64e8f1c84e0166d9e50405d7a",
        md5: "66608a96a4f2d73b4a1d054e76e6eae4",
      },
      caution: { zh: "专家级资源，仅提供英文版。首次启动后请手动切换系统语言和时区，并安装 CJK 字体包以正确显示中日韩文字。请确认设备适配、许可与使用范围。", en: "Expert-level resource. Confirm device suitability, licensing, and allowed use." },
      languageNotice: { zh: "IoT LTSC 语言提示：仅提供英文版；123 云盘和国际渠道均为英文版。", en: "IoT LTSC language note: only English builds are provided; both 123 Cloud and International Channel provide the English build." },
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
      size: "244.83 MB",
      copy: { zh: "为 Tiny10、Tiny11 与 Windows X-Lite 补充 CJK 文本显示。", en: "Supplementary CJK text rendering for Tiny10, Tiny11, and Windows X-Lite." },
      workflows: ["install"],
      chinaLink: "https://1842249449.share.123pan.cn/123pan/Z4L0Td-7MR0h",
      showInternationalDownload: false,
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
  const displayValue = (value) => typeof value === "string" ? value : localized(value);
  const isChineseLanguage = () => ["zh", "zh_TW"].includes(language());

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
        node("span", "", displayValue(item.size)),
      );
      const action = node("button", "button button-secondary", t("image_view"));
      action.type = "button";
      action.addEventListener("click", () => openItem(item.id));
      card.append(top, title, copy, facts, action);
      root.append(card);
    });
  }

  function makeFact(label, value, className = "") {
    const item = node("div", className);
    item.append(node("dt", "", label), node("dd", "", value));
    return item;
  }

  function safeExternalUrl(value) {
    try {
      const url = new URL(value);
      return url.protocol === "https:" ? url.href : "";
    } catch (_) {
      return "";
    }
  }

  function downloadSource(title, copy, href, primary = false, appDownload = false) {
    const source = node("div", "source-option");
    if (title || copy) {
      const sourceCopy = node("div");
      if (title) sourceCopy.append(node("h4", "", title));
      if (copy) sourceCopy.append(node("p", "", copy));
      source.append(sourceCopy);
    } else {
      source.classList.add("source-option-single");
    }

    const safeUrl = safeExternalUrl(href);
    if (safeUrl) {
      const action = node("a", `button ${primary ? "button-primary" : "button-secondary"}`, t("image_download"));
      action.href = safeUrl;
      action.target = "_blank";
      action.rel = "noreferrer";
      if (appDownload) action.dataset.wdsDownload = "true";
      source.append(action);
    } else {
      const pending = node("button", "button button-secondary", t("image_download"));
      pending.type = "button";
      pending.disabled = true;
      source.append(pending);
    }
    return source;
  }

  function downloadSources(item) {
    const sources = node("div", "download-sources");
    const officialLink = safeExternalUrl(item.officialLink?.[language()]);
    const chinaLink = language() === "zh" ? safeExternalUrl(item.chinaLink) : "";
    const preferredSource = new URLSearchParams(window.location.search).get("source");
    const internationalLink = safeExternalUrl(item.internationalLink);
    const hasInternational = item.showInternationalDownload !== false && Boolean(internationalLink);
    const addChina = (primary = false) => {
      if (chinaLink) {
        sources.append(downloadSource(t("image_123pan_link"), t("image_123pan_copy"), chinaLink, primary));
      }
    };
    const addInternational = (primary = false) => {
      if (hasInternational) {
        sources.append(downloadSource(t("image_international_link"), t("image_international_copy"), internationalLink, primary, true));
      }
    };

    // Chinese official Windows images prioritize Microsoft's own download page.
    // Do not offer the international mirror for these entries.
    if (language() === "zh" && item.source === "official" && officialLink) {
      sources.append(downloadSource(t("image_microsoft_link"), t("image_microsoft_copy"), officialLink, true));
      addChina();
      return sources;
    }

    if (preferredSource === "global") {
      addInternational(true);
      addChina();
    } else {
      addChina(true);
      addInternational();
    }

    if (officialLink) {
      sources.append(downloadSource(t("image_microsoft_link"), t("image_microsoft_copy"), officialLink, !chinaLink));
    }

    if (!sources.childElementCount) sources.append(downloadSource("", "", ""));
    return sources;
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
      makeFact(t("image_size"), displayValue(item.size)),
      makeFact(t("image_workflows"), item.workflows.map(workflowLabel).join(" · ")),
      makeFact(t("image_version"), item.version),
    );
    if (item.checksums && (!item.checksums.nonChineseOnly || !isChineseLanguage())) {
      facts.append(
        makeFact("SHA-256", item.checksums.sha256, "checksum-fact"),
        makeFact("MD5", item.checksums.md5, "checksum-fact"),
      );
    }
    body.append(facts);
    const caution = localized(item.caution);
    if (caution) body.append(node("div", "notice", caution));
    const languageNotice = localized(item.languageNotice);
    if (languageNotice) body.append(node("div", "notice image-language-notice", languageNotice));
    body.append(node("h3", "", t("image_download_sources")));
    body.append(downloadSources(item));
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
