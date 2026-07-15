(() => {
  "use strict";

  const STORAGE = {
    language: "wds-pages-language",
    theme: "wds-pages-theme",
  };

  const translations = {
    zh: {
      skip_to_content: "跳到主要内容",
      nav_product: "产品",
      nav_downloads: "下载",
      nav_images: "镜像",
      nav_github: "GitHub",
      nav_open: "打开导航",
      nav_close: "关闭导航",
      theme_light: "切换到明亮模式",
      theme_dark: "切换到黑夜模式",
      hero_eyebrow: "Windows 与 Linux 部署工具",
      hero_copy: "在一个安静、可靠的桌面工作区中创建安装介质、随身系统并检查存储设备。",
      hero_download: "下载最新版",
      hero_images: "浏览镜像",
      hero_release: "最新 GitHub Release",
      hero_scroll: "探索功能",
      hero_preview_alt: "WinDeploy Studio 首页、快速开始和工作区",
      capabilities_eyebrow: "核心工作流",
      capabilities_title: "从镜像到可启动设备",
      capabilities_copy: "清晰地组织每一步，并在破坏性操作之前保留必要的确认和校验。",
      feature_media_title: "安装介质",
      feature_media_copy: "创建 Windows 安装盘，或验证并写入 Linux ISOHybrid 镜像。",
      feature_togo_title: "To Go 工作区",
      feature_togo_copy: "使用结构预检、磁盘身份保护和适配的启动布局创建便携工作区。",
      feature_disk_title: "磁盘分析",
      feature_disk_copy: "检测速度、稳定性、健康数据和适合随身系统的实际表现。",
      safety_eyebrow: "部署前检查",
      safety_title: "让每一次写入都有依据",
      safety_copy: "从 ISO 结构、目标磁盘身份到写入后校验，关键步骤会在真正清除数据前重新确认。",
      demo_eyebrow: "产品演示",
      demo_title: "完整工作区，一目了然",
      demo_copy: "轮播展示 WinDeploy Studio 的全部主要界面。",
      download_band_eyebrow: "保持最新",
      download_band_title: "从可信发布源获取安装包",
      download_band_action: "查看下载与更新说明",
      footer_copy: "面向 Windows 与 Linux 部署工作流的桌面工具。",
      footer_license: "MIT License",
      footer_global_mirror: "SourceForge",
      downloads_eyebrow: "应用下载",
      downloads_title: "最新版与更新记录",
      downloads_copy: "更新说明来自 GitHub Releases；SourceForge 提供可选下载源。下载前会展示文件大小和 SHA-256 摘要。",
      latest_eyebrow: "推荐版本",
      latest_title: "最新稳定版",
      history_eyebrow: "发行历史",
      history_title: "历史版本",
      release_loading: "正在读取发布信息...",
      release_failed: "暂时无法读取发行信息。",
      release_open_github: "在 GitHub 查看",
      release_download_github: "从 GitHub 下载",
      release_sourceforge: "SourceForge（推荐）",
      release_download_sourceforge: "从 SourceForge 下载",
      release_sourceforge_copy: "推荐下载源，提供安装包镜像下载。",
      release_github_copy: "备用下载源。",
      release_notes: "更新说明",
      release_no_notes: "该版本没有提供更新说明。",
      release_file: "安装包",
      release_sha256: "SHA-256",
      release_published: "发布时间",
      release_size: "大小",
      release_asset_unavailable: "未找到 Windows 安装包",
      release_prerelease: "预发布",
      images_eyebrow: "镜像目录",
      images_title: "选择适合的部署镜像",
      images_copy: "参考应用内的镜像中心，按来源、用途和风险级别查看镜像。下载链接会在对应文件可用时启用。",
      catalog_eyebrow: "镜像库",
      catalog_title: "按来源和适用程度筛选",
      filter_all: "全部",
      filter_official: "官方来源",
      filter_community: "社区镜像",
      filter_enterprise: "企业与 LTSC",
      filter_tools: "工具与字体",
      image_view: "查看与下载",
      image_source: "来源",
      image_level: "适用程度",
      image_architecture: "架构",
      image_version: "版本",
      image_size: "文件大小",
      image_workflows: "适用工作流",
      image_download_sources: "下载镜像",
      image_download: "下载镜像",
      image_microsoft_link: "Microsoft 官方链接",
      image_microsoft_copy: "从 Microsoft 官方网站下载。",
      image_123pan_link: "123 云盘链接",
      image_123pan_copy: "更适合国内用户。",
      image_international_link: "下载镜像",
      image_international_copy: "国际渠道下载。",
      image_placeholder_title: "下载映射准备中",
      image_placeholder_copy: "该镜像的下载链接尚未配置。",
      image_close: "关闭",
      level_beginner: "入门",
      level_advanced: "高级",
      level_expert: "专家",
      category_official: "官方镜像",
      category_community: "社区镜像",
      category_enterprise: "企业与 LTSC",
      category_tools: "工具与字体",
      source_official: "官方来源",
      source_community: "第三方社区",
      source_release: "发布文件",
      workflow_install: "安装盘",
      workflow_togo: "Windows To Go",
      workflow_ltg: "Linux To Go",
      carousel_previous: "上一张演示图",
      carousel_next: "下一张演示图",
      carousel_pause: "暂停轮播",
      carousel_play: "播放轮播",
      carousel_position: "第 {current} 张，共 {total} 张",
    },
    en: {
      skip_to_content: "Skip to main content",
      nav_product: "Product",
      nav_downloads: "Downloads",
      nav_images: "Images",
      nav_github: "GitHub",
      nav_open: "Open navigation",
      nav_close: "Close navigation",
      theme_light: "Switch to light mode",
      theme_dark: "Switch to dark mode",
      hero_eyebrow: "Windows & Linux Deployment Toolkit",
      hero_copy: "Create installation media, portable workspaces, and inspect storage from one quiet, reliable desktop workspace.",
      hero_download: "Download latest",
      hero_images: "Browse images",
      hero_release: "Latest GitHub Release",
      hero_scroll: "Explore features",
      hero_preview_alt: "WinDeploy Studio home, Quick Start, and workspace",
      capabilities_eyebrow: "Core workflows",
      capabilities_title: "From image to bootable device",
      capabilities_copy: "Keep each step clear, with the confirmation and verification that destructive work deserves.",
      feature_media_title: "Installation media",
      feature_media_copy: "Create Windows installation media or validate and write Linux ISOHybrid images.",
      feature_togo_title: "To Go workspaces",
      feature_togo_copy: "Build portable workspaces with structural preflight, disk identity protection, and appropriate boot layouts.",
      feature_disk_title: "Storage analysis",
      feature_disk_copy: "Measure speed, stability, health data, and practical suitability for portable systems.",
      safety_eyebrow: "Pre-deployment checks",
      safety_title: "Give every write a basis",
      safety_copy: "ISO structure, target disk identity, and post-write verification are revisited before data is actually erased.",
      demo_eyebrow: "Product tour",
      demo_title: "The complete workspace, at a glance",
      demo_copy: "A rotating view of every major WinDeploy Studio surface.",
      download_band_eyebrow: "Stay current",
      download_band_title: "Get verified installers from trusted release sources",
      download_band_action: "Downloads and release notes",
      footer_copy: "A desktop toolkit for Windows and Linux deployment workflows.",
      footer_license: "MIT License",
      footer_global_mirror: "SourceForge",
      downloads_eyebrow: "App downloads",
      downloads_title: "Latest builds and release history",
      downloads_copy: "Release notes come from GitHub Releases, with SourceForge available as an optional download source. File size and SHA-256 are shown before download.",
      latest_eyebrow: "Recommended build",
      latest_title: "Latest stable release",
      history_eyebrow: "Release history",
      history_title: "Previous versions",
      release_loading: "Loading release information...",
      release_failed: "Release information is temporarily unavailable.",
      release_open_github: "View on GitHub",
      release_download_github: "Download from GitHub",
      release_sourceforge: "SourceForge (Recommended)",
      release_download_sourceforge: "Download from SourceForge",
      release_sourceforge_copy: "Recommended mirror source for installer downloads.",
      release_github_copy: "Fallback download source.",
      release_notes: "Release notes",
      release_no_notes: "No release notes were provided for this version.",
      release_file: "Installer",
      release_sha256: "SHA-256",
      release_published: "Published",
      release_size: "Size",
      release_asset_unavailable: "No Windows installer found",
      release_prerelease: "Pre-release",
      images_eyebrow: "Image directory",
      images_title: "Choose an image for the job",
      images_copy: "Like the application Image Center, browse by source, purpose, and suitability level. Download links are enabled as the corresponding files become available.",
      catalog_eyebrow: "Image library",
      catalog_title: "Filter by source and suitability",
      filter_all: "All",
      filter_official: "Official",
      filter_community: "Community",
      filter_enterprise: "Enterprise & LTSC",
      filter_tools: "Tools & fonts",
      image_view: "View and download",
      image_source: "Source",
      image_level: "Suitability",
      image_architecture: "Architecture",
      image_version: "Version",
      image_size: "File size",
      image_workflows: "Workflows",
      image_download_sources: "Download image",
      image_download: "Download image",
      image_microsoft_link: "Microsoft official link",
      image_microsoft_copy: "Download from the official Microsoft website.",
      image_123pan_link: "123 Cloud Drive link",
      image_123pan_copy: "Better suited to users in mainland China.",
      image_international_link: "Download image",
      image_international_copy: "International download channel.",
      image_placeholder_title: "Download mapping pending",
      image_placeholder_copy: "A download link is not configured for this image yet.",
      image_close: "Close",
      level_beginner: "Beginner",
      level_advanced: "Advanced",
      level_expert: "Expert",
      category_official: "Official images",
      category_community: "Community images",
      category_enterprise: "Enterprise & LTSC",
      category_tools: "Tools & fonts",
      source_official: "Official source",
      source_community: "Third-party community",
      source_release: "Release files",
      workflow_install: "Install media",
      workflow_togo: "Windows To Go",
      workflow_ltg: "Linux To Go",
      carousel_previous: "Previous demo image",
      carousel_next: "Next demo image",
      carousel_pause: "Pause carousel",
      carousel_play: "Play carousel",
      carousel_position: "Image {current} of {total}",
    },
  };

  const demoSlides = [
    ["1.png", "首页：标题、快速开始与工作区", "Home: Title, Quick Start, and Workspace", "在首页概览主要入口、快速开始和工作区状态", "An overview of the title, Quick Start, and workspace status"],
    ["2.png", "首页：关于", "Home: About", "查看项目、版本与应用信息", "Review project, version, and application information"],
    ["3.png", "镜像库", "Image Library", "按来源与适用程度浏览镜像资源", "Browse image resources by source and suitability"],
    ["4.png", "Windows 安装盘", "Windows Installation Media", "选择 Windows ISO 并创建安装介质", "Choose a Windows ISO and create installation media"],
    ["5.png", "Linux 安装盘", "Linux Installation Media", "验证 Linux 镜像并写入可启动设备", "Validate a Linux image and write a bootable device"],
    ["6.png", "Windows To Go", "Windows To Go", "配置便携 Windows 工作区", "Configure a portable Windows workspace"],
    ["7.png", "Linux To Go", "Linux To Go", "创建受支持发行版的便携工作区", "Create a portable workspace for supported distributions"],
    ["8.png", "磁盘测试", "Disk Test", "评估顺序、随机和稳定性表现", "Measure sequential, random, and stability performance"],
    ["9.png", "磁盘工具", "Disk Tools", "集中访问存储设备与分区工具", "Access storage-device and partitioning tools"],
    ["10.png", "磁盘诊断", "Disk Diagnostics", "读取健康、温度和可靠性信息", "Read health, temperature, and reliability information"],
    ["11.png", "BCD/EFI 启动修复", "BCD/EFI Boot Repair", "对经过重新验证的外接磁盘执行受保护的启动修复", "Perform guarded boot repair on a revalidated external disk"],
    ["12.png", "日志中心（一）", "Log Center (1)", "按类别和活动概览浏览日志", "Browse logs by category and activity overview"],
    ["13.png", "日志中心（二）", "Log Center (2)", "查看更新、错误与操作记录", "Review updates, errors, and operation records"],
    ["14.png", "AI 助手", "AI Assistant", "获取部署建议和诊断支持", "Get deployment guidance and diagnostic support"],
    ["15.png", "工具", "Tools", "查看精选实用工具与用途说明", "Explore curated utilities and their purpose"],
    ["16.png", "设置（一）", "Settings (1)", "管理应用的基础偏好", "Manage core application preferences"],
    ["17.png", "设置（二）", "Settings (2)", "调整语言、外观和相关选项", "Adjust language, appearance, and related options"],
    ["18.png", "设置（三）", "Settings (3)", "查看其余设置与应用信息", "Review remaining settings and application information"],
  ].map(([file, zhTitle, enTitle, zhCopy, enCopy]) => ({
    file,
    title: { zh: zhTitle, en: enTitle },
    copy: { zh: zhCopy, en: enCopy },
  }));

  function getRoot() {
    return document.body?.dataset.root || "./";
  }

  function getLanguage() {
    return document.documentElement.lang === "en" ? "en" : "zh";
  }

  function t(key, values = {}) {
    const raw = translations[getLanguage()][key] || translations.zh[key] || key;
    return raw.replace(/\{(\w+)\}/g, (_, name) => values[name] ?? `{${name}}`);
  }

  function refreshIcons() {
    if (window.lucide?.createIcons) {
      window.lucide.createIcons({ attrs: { "aria-hidden": "true" } });
    }
  }

  function applyTranslations() {
    document.querySelectorAll("[data-i18n]").forEach((element) => {
      element.textContent = t(element.dataset.i18n);
    });
    document.querySelectorAll("[data-i18n-aria-label]").forEach((element) => {
      element.setAttribute("aria-label", t(element.dataset.i18nAriaLabel));
    });
    document.querySelectorAll("[data-i18n-title]").forEach((element) => {
      element.setAttribute("title", t(element.dataset.i18nTitle));
    });
    document.querySelectorAll("[data-i18n-alt]").forEach((element) => {
      element.setAttribute("alt", t(element.dataset.i18nAlt));
    });
  }

  function renderShell() {
    const root = getRoot();
    const page = document.body.dataset.page;
    const isDark = document.documentElement.dataset.theme === "dark";
    const header = document.querySelector("#site-header");
    const footer = document.querySelector("#site-footer");

    if (header) {
      header.innerHTML = `
        <header class="site-header">
          <div class="nav-wrap content-width">
            <a class="brand" href="${root}" aria-label="WinDeploy Studio home">
              <img src="${root}assets/media/logo.png" alt="" />
              <span>WinDeploy Studio</span>
            </a>
            <button class="icon-button nav-menu-toggle" type="button" data-menu-toggle aria-controls="site-navigation" aria-expanded="false" data-i18n-aria-label="nav_open" data-i18n-title="nav_open" title="${t("nav_open")}">
              <i data-lucide="menu"></i>
            </button>
            <nav id="site-navigation" class="site-nav" aria-label="Primary navigation">
              <a href="${root}" ${page === "home" ? 'aria-current="page"' : ""}><span data-i18n="nav_product">产品</span></a>
              <a href="${root}downloads/" ${page === "downloads" ? 'aria-current="page"' : ""}><span data-i18n="nav_downloads">下载</span></a>
              <a href="${root}images/" ${page === "images" ? 'aria-current="page"' : ""}><span data-i18n="nav_images">镜像</span></a>
              <a href="https://github.com/intelfans/WinDeployStudio" target="_blank" rel="noreferrer"><span data-i18n="nav_github">GitHub</span></a>
            </nav>
            <div class="nav-controls">
              <div class="language-switch" aria-label="Language">
                <button type="button" data-language="zh" aria-pressed="${getLanguage() === "zh"}">中文</button>
                <button type="button" data-language="en" aria-pressed="${getLanguage() === "en"}">EN</button>
              </div>
              <button class="icon-button" type="button" data-theme-toggle data-i18n-aria-label="${isDark ? "theme_light" : "theme_dark"}" data-i18n-title="${isDark ? "theme_light" : "theme_dark"}" title="${t(isDark ? "theme_light" : "theme_dark")}">
                <i data-lucide="${isDark ? "sun" : "moon"}"></i>
              </button>
            </div>
          </div>
        </header>`;
    }

    if (footer) {
      footer.innerHTML = `
        <footer class="site-footer">
          <div class="footer-wrap content-width">
            <p data-i18n="footer_copy">面向 Windows 与 Linux 部署工作流的桌面工具。</p>
            <div class="footer-links">
              <a href="https://github.com/intelfans/WinDeployStudio" target="_blank" rel="noreferrer">GitHub</a>
              <a href="https://sourceforge.net/projects/windeploystudio/" target="_blank" rel="noreferrer" data-i18n="footer_global_mirror">SourceForge</a>
              <a href="https://github.com/intelfans/WinDeployStudio/blob/main/LICENSE" target="_blank" rel="noreferrer" data-i18n="footer_license">MIT License</a>
            </div>
          </div>
        </footer>`;
    }
  }

  function setTheme(theme) {
    const next = theme === "dark" ? "dark" : "light";
    document.documentElement.dataset.theme = next;
    document.querySelector('meta[name="theme-color"]')?.setAttribute("content", next === "dark" ? "#000000" : "#f5f5f7");
    localStorage.setItem(STORAGE.theme, next);
    renderShell();
    applyTranslations();
    refreshIcons();
  }

  function setLanguage(language) {
    const next = language === "en" ? "en" : "zh";
    document.documentElement.lang = next === "en" ? "en" : "zh-CN";
    localStorage.setItem(STORAGE.language, next);
    renderShell();
    applyTranslations();
    refreshIcons();
    document.dispatchEvent(new CustomEvent("wds:languagechange", { detail: next }));
  }

  function setupControls() {
    document.addEventListener("click", (event) => {
      const languageButton = event.target.closest("[data-language]");
      if (languageButton) {
        setLanguage(languageButton.dataset.language);
        return;
      }
      if (event.target.closest("[data-theme-toggle]")) {
        setTheme(document.documentElement.dataset.theme === "dark" ? "light" : "dark");
        return;
      }
      const menuToggle = event.target.closest("[data-menu-toggle]");
      if (menuToggle) {
        const header = menuToggle.closest(".site-header");
        const isOpen = !header.classList.contains("nav-open");
        header.classList.toggle("nav-open", isOpen);
        menuToggle.setAttribute("aria-expanded", String(isOpen));
        menuToggle.setAttribute("aria-label", t(isOpen ? "nav_close" : "nav_open"));
        menuToggle.setAttribute("title", t(isOpen ? "nav_close" : "nav_open"));
        menuToggle.innerHTML = `<i data-lucide="${isOpen ? "x" : "menu"}"></i>`;
        refreshIcons();
        return;
      }
      const openHeader = document.querySelector(".site-header.nav-open");
      if (openHeader && !event.target.closest(".site-header")) {
        const openToggle = openHeader.querySelector("[data-menu-toggle]");
        openHeader.classList.remove("nav-open");
        openToggle?.setAttribute("aria-expanded", "false");
        openToggle?.setAttribute("aria-label", t("nav_open"));
        openToggle?.setAttribute("title", t("nav_open"));
        if (openToggle) openToggle.innerHTML = '<i data-lucide="menu"></i>';
        refreshIcons();
      }
    });
    document.addEventListener("keydown", (event) => {
      if (event.key !== "Escape") return;
      const openHeader = document.querySelector(".site-header.nav-open");
      const openToggle = openHeader?.querySelector("[data-menu-toggle]");
      if (!openHeader || !openToggle) return;
      openHeader.classList.remove("nav-open");
      openToggle.setAttribute("aria-expanded", "false");
      openToggle.setAttribute("aria-label", t("nav_open"));
      openToggle.setAttribute("title", t("nav_open"));
      openToggle.innerHTML = '<i data-lucide="menu"></i>';
      refreshIcons();
    });
  }

  function makeCarousel() {
    const root = document.querySelector("#demo-carousel");
    if (!root) return;

    let current = 0;
    let paused = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    let timer = null;

    const stop = () => {
      if (timer !== null) window.clearInterval(timer);
      timer = null;
    };
    const start = () => {
      stop();
      if (!paused) timer = window.setInterval(() => show((current + 1) % demoSlides.length), 5600);
    };
    const show = (index) => {
      current = (index + demoSlides.length) % demoSlides.length;
      root.querySelectorAll(".carousel-slide").forEach((slide, slideIndex) => {
        slide.classList.toggle("is-active", slideIndex === current);
        slide.setAttribute("aria-hidden", String(slideIndex !== current));
      });
      root.querySelectorAll(".carousel-dot").forEach((dot, dotIndex) => {
        dot.setAttribute("aria-current", String(dotIndex === current));
      });
      const copy = demoSlides[current];
      root.querySelector("[data-carousel-title]").textContent = copy.title[getLanguage()];
      root.querySelector("[data-carousel-copy]").textContent = copy.copy[getLanguage()];
      root.querySelector("[data-carousel-position]").textContent = t("carousel_position", { current: current + 1, total: demoSlides.length });
      start();
    };
    const render = () => {
      root.innerHTML = "";
      const stage = document.createElement("div");
      stage.className = "carousel-stage";
      demoSlides.forEach((slide, index) => {
        const item = document.createElement("figure");
        item.className = `carousel-slide${index === current ? " is-active" : ""}`;
        item.setAttribute("aria-hidden", String(index !== current));
        const image = document.createElement("img");
        image.src = `${getRoot()}assets/media/${slide.file}`;
        image.alt = slide.title[getLanguage()];
        image.loading = index === 0 ? "eager" : "lazy";
        item.append(image);
        stage.append(item);
      });
      const footer = document.createElement("div");
      footer.className = "carousel-footer";
      footer.innerHTML = `
        <div class="carousel-copy">
          <h3 data-carousel-title></h3>
          <p data-carousel-copy></p>
        </div>
        <div class="carousel-controls">
          <button class="icon-button" type="button" data-carousel-previous title="${t("carousel_previous")}" aria-label="${t("carousel_previous")}"><i data-lucide="chevron-left"></i></button>
          <button class="icon-button" type="button" data-carousel-toggle title="${paused ? t("carousel_play") : t("carousel_pause")}" aria-label="${paused ? t("carousel_play") : t("carousel_pause")}"><i data-lucide="${paused ? "play" : "pause"}"></i></button>
          <button class="icon-button" type="button" data-carousel-next title="${t("carousel_next")}" aria-label="${t("carousel_next")}"><i data-lucide="chevron-right"></i></button>
          <span class="carousel-position" data-carousel-position></span>
        </div>`;
      const dots = document.createElement("div");
      dots.className = "carousel-dots";
      demoSlides.forEach((slide, index) => {
        const dot = document.createElement("button");
        dot.type = "button";
        dot.className = "carousel-dot";
        dot.dataset.carouselIndex = String(index);
        dot.setAttribute("aria-label", `${slide.title[getLanguage()]} (${index + 1})`);
        dot.setAttribute("aria-current", String(index === current));
        dots.append(dot);
      });
      root.append(stage, footer, dots);
      root.querySelector("[data-carousel-previous]").addEventListener("click", () => show(current - 1));
      root.querySelector("[data-carousel-next]").addEventListener("click", () => show(current + 1));
      root.querySelector("[data-carousel-toggle]").addEventListener("click", (event) => {
        paused = !paused;
        event.currentTarget.setAttribute("aria-label", paused ? t("carousel_play") : t("carousel_pause"));
        event.currentTarget.setAttribute("title", paused ? t("carousel_play") : t("carousel_pause"));
        event.currentTarget.innerHTML = `<i data-lucide="${paused ? "play" : "pause"}"></i>`;
        refreshIcons();
        start();
      });
      root.querySelectorAll("[data-carousel-index]").forEach((dot) => dot.addEventListener("click", () => show(Number(dot.dataset.carouselIndex))));
      root.onmouseenter = stop;
      root.onmouseleave = start;
      root.onfocusin = stop;
      root.onfocusout = start;
      show(current);
      refreshIcons();
    };

    document.addEventListener("visibilitychange", () => {
      if (document.hidden) stop();
      else start();
    });

    render();
    document.addEventListener("wds:languagechange", () => {
      stop();
      render();
    });
  }

  const queryLanguage = new URLSearchParams(window.location.search).get("lang");
  const preferredTheme = localStorage.getItem(STORAGE.theme) || (window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light");
  const preferredLanguage = queryLanguage === "en" || queryLanguage === "zh"
    ? queryLanguage
    : localStorage.getItem(STORAGE.language) || "zh";
  document.documentElement.dataset.theme = preferredTheme === "dark" ? "dark" : "light";
  document.documentElement.lang = preferredLanguage === "en" ? "en" : "zh-CN";

  window.WDS = {
    t,
    getRoot,
    getLanguage,
    refreshIcons,
    setLanguage,
  };

  document.addEventListener("DOMContentLoaded", () => {
    renderShell();
    applyTranslations();
    setupControls();
    makeCarousel();
    refreshIcons();
  });
})();
