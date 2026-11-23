(() => {
  const REPO = "athlan20/peek";
  const FALLBACK_VERSION = "0.1.3";

  const I18N = {
    zh: {
      pageTitle: "Peek — 轻量、原生的 macOS 菜单栏系统监控与清理工具",
      pageDesc: "100% 原生 Swift & SwiftUI 打造的 macOS 菜单栏工具：实时硬件 Bento 监控面板、可视化磁盘与 AI Agent 空间分析、应用彻底卸载。",
      "nav.features": "功能特性",
      "nav.analyze": "磁盘与 Agent",
      "nav.uninstall": "应用卸载",
      "nav.install": "安装指南",
      "nav.download": "下载",
      "hero.eyebrow": "macOS 14+ · 100% 原生 Swift & SwiftUI · 开源免费",
      "hero.title": "轻点菜单栏，<br />洞悉 Mac 的每一寸状态。",
      "hero.subtitle": "常驻于 macOS 菜单栏的高密度暗色 Bento 监控面板，集成实时硬件遥测、交互式磁盘与 AI Agent 空间方块分析，以及支持残留清理的应用卸载器。零外部依赖，后台接近零开销。",
      "hero.dlArm": "下载 Apple Silicon 版",
      "hero.dlIntel": "Intel Mac 版",
      "hero.releaseLoading": "最新版本：v{ver} · 支持 macOS 14 Sonoma 及以上",
      "hero.allReleases": "所有版本 ↗",
      "trust.native": "原生 Darwin / IOKit",
      "trust.idle": "收起后后台占用",
      "trust.agents": "AI Agent 占用识别",
      "trust.noRoot": "无需管理员权限",
      "bento.kicker": "BENTO 菜单栏面板",
      "bento.title": "6 张卡片，一屏看清所有核心硬件指标",
      "bento.desc": "拒绝杂乱的二级菜单。打开弹出面板即刻高频采样，收起瞬间归零休眠；悬停任意卡片还可展开精简细节。",
      "bento.cpu.badge": "P/E 核心矩阵",
      "bento.cpu.title": "处理器与进程方块",
      "bento.cpu.desc": "实时展示总占用率、性能核与能效核（P/E Cores）负载点阵，以及高占用进程的迷你方块图，异常飙升一眼定位。",
      "bento.mem.badge": "压力 & Swap",
      "bento.mem.title": "对齐活动监视器的内存视图",
      "bento.mem.desc": "与 macOS 活动监视器口径一致的已用 / 总内存统计，配备内存压力与 Swap 指示灯，直观列出最吃内存的应用。",
      "bento.storage.badge": "读写速率 & 分类",
      "bento.storage.title": "存储容量像素矩阵",
      "bento.storage.desc": "实时监测磁盘读写吞吐（R/W MB/s），用像素点阵按 system、Apps、user、cache、free 清晰呈现空间分布。",
      "bento.network.badge": "本地端口识别",
      "bento.network.title": "网速与监听端口表",
      "bento.network.desc": "展示默认网卡实时上下行速率，并自动扫描本地监听端口与服务分类（Web、AI、DB、Proxy，如 node、ollama 等）。",
      "bento.battery.badge": "USB-C PD & 功耗",
      "bento.battery.title": "电池健康与实时功耗",
      "bento.battery.desc": "电量、循环次数、四格健康度矩阵一目了然；同时读取 USB-C PD 充电器功率规格与整机实时功耗（W）。",
      "bento.thermal.badge": "温控 & 风扇",
      "bento.thermal.title": "多传感器温度与转速",
      "bento.thermal.desc": "实时读取 CPU、GPU、SSD 温度柱状条（°C）、温控状态徽标、风扇转速（RPM）以及运行期间的峰值温度记录。",
      "analyze.kicker": "ANALYZE · 磁盘与 AI AGENT 空间分析",
      "analyze.title": "边扫边画的方块视图，揪出隐藏的体积大户",
      "analyze.desc": "纯 Swift 实现的 Squarified Treemap 布局引擎，每 0.2 秒实时刷新快照，无需等整盘扫完即可双击逐层下钻。支持断点暂停与持久化缓存，关闭窗口也不丢失进度。",
      "analyze.f1.title": "流式扫描 & 断点续扫",
      "analyze.f1.desc": "扫描检查点自动持久化至本地缓存。随时暂停、关闭窗口或重启应用，下次打开无缝接着扫。",
      "analyze.f2.title": "语义化自动着色",
      "analyze.f2.desc": "自动区分 Apps、Dev（node_modules、DerivedData、.cargo 等）、Agents、Media、Docs 与 System，一眼辨识可清理项。",
      "analyze.f3.title": "久置下载专项清理",
      "analyze.f3.desc": "独立筛选 ~/Downloads 中超过 90 天未碰过的大文件与安装包，一键在访达中定位或安全移入废纸篓。",
      "analyze.agentsTitle": "内置 19+ 主流 AI 编程工具与本地模型占用专页",
      "analyze.agentsDesc": "自动聚合散落在主目录与资源库中的模型权重、缓存与会话记录：",
      "uninstall.kicker": "UNINSTALL · 可视化应用卸载器",
      "uninstall.title": "按体积排布、按使用频率着色，连同残留一并清干净",
      "uninstall.desc": "扫描 /Applications 与 ~/Applications，根据 Spotlight 最后使用时间（7 天内 → 1 年以上）为每个应用方块着色，帮你迅速找出又大又久未打开的软件。",
      "uninstall.f1.title": "深层 ~/Library 残留关联",
      "uninstall.f1.desc": "按 Bundle ID 与应用名精准匹配 Application Support、Caches、Preferences、Containers、Saved State、Logs 等关联目录。",
      "uninstall.f2.title": "多重安全防误删",
      "uninstall.f2.desc": "系统内置应用与 Peek 自身自动加锁；运行中的应用标有运行角标并提示先退出，避免误操作。",
      "uninstall.f3.title": "先预览，统一移至废纸篓",
      "uninstall.f3.desc": "每次卸载都会完整列出即将清理的路径与体积，确认后统一移入废纸篓而非永久静默删除，随时可反悔。",
      "arch.kicker": "原生架构与隐私安全",
      "arch.title": "轻巧克制，把控制权完全留给你",
      "arch.p1.title": "零后台常驻开销",
      "arch.p1.desc": "仅在面板展开时进行高频采样，收起后立即停止采集，日常挂在菜单栏几乎不消耗电量与 CPU。",
      "arch.p2.title": "权限优雅降级",
      "arch.p2.desc": "全程以普通用户运行，无需管理员密码；完全磁盘访问权限（FDA）完全可选，未授权也能正常使用核心功能。",
      "arch.p3.title": "双重校验在线更新",
      "arch.p3.desc": "内置 GitHub Releases 更新器，自动匹配芯片架构，下载后同时校验 SHA-256 摘要与代码签名证书指纹。",
      "arch.p4.title": "中英双语即时切换",
      "arch.p4.desc": "应用内置简体中文、English 与跟随系统选项，设置中切换后立即生效，无需重启应用。",
      "install.kicker": "下载与安装",
      "install.title": "30 秒装好，即刻在菜单栏启用 Peek",
      "install.desc": "支持 macOS 14.0 (Sonoma) 及以上版本，提供 Apple Silicon 与 Intel 独立安装包。",
      "install.downloadTitle": "下载安装包",
      "install.downloadDesc": "选择匹配你 Mac 芯片的 .dmg 安装包，打开后将 Peek 拖入“应用程序（Applications）”文件夹即可。",
      "install.armTitle": "Apple Silicon (M1 / M2 / M3 / M4)",
      "install.intelTitle": "Intel Mac (x86_64)",
      "install.checksums": "查看 Release 说明与 SHA256SUMS ↗",
      "install.fromSource": "从源码构建 ↗",
      "install.gatekeeperTitle": "首次打开说明（Gatekeeper）",
      "install.gatekeeperDesc": "Peek 采用固定的自签名证书签名（以保证后续在线更新时系统隐私授权不会丢失），未走 Apple 公证。首次打开遇到系统拦截时，只需操作一次：",
      "install.step1": "在弹窗中点击 <strong>“完成”</strong>（不要点“移到废纸篓”）。",
      "install.step2": "前往 <strong>系统设置 → 隐私与安全性</strong>，向下滚动到“安全性”区域，点击 Peek 旁的 <strong>“仍要打开”</strong>。",
      "install.step3": "使用触控 ID 或密码确认，再次打开 Peek 即可正常使用。",
      "install.terminalTip": "或在终端移除隔离标记：",
      "install.copy": "复制",
      "install.copied": "已复制",
      "footer.tagline": "轻量、原生的 macOS 菜单栏系统监控与清理工具",
      "footer.releases": "版本发布",
      "footer.issues": "问题反馈",
      "footer.origin": "项目首发于 Linux.do 社区 · Built with native Swift & SwiftUI"
    },
    en: {
      pageTitle: "Peek — Native macOS Menu Bar System Monitor, Disk Analyzer & App Uninstaller",
      pageDesc: "A lightweight, 100% native macOS menu bar app for real-time hardware telemetry, visual disk & AI Agent footprint analysis, and clean app uninstallation.",
      "nav.features": "Features",
      "nav.analyze": "Analyze & Agents",
      "nav.uninstall": "Uninstaller",
      "nav.install": "Install",
      "nav.download": "Download",
      "hero.eyebrow": "macOS 14+ · 100% Native Swift & SwiftUI · Open Source",
      "hero.title": "See what your Mac is doing,<br />in one glance.",
      "hero.subtitle": "A high-density dark Bento dashboard living quietly in your macOS menu bar—combining real-time hardware telemetry, streaming disk & AI Agent treemaps, and a leftover-aware app uninstaller. Zero external CLI dependencies, near-zero idle CPU.",
      "hero.dlArm": "Download for Apple Silicon",
      "hero.dlIntel": "Intel Mac",
      "hero.releaseLoading": "Latest: v{ver} · Requires macOS 14 Sonoma or later",
      "hero.allReleases": "All Releases ↗",
      "trust.native": "Native Darwin / IOKit",
      "trust.idle": "Idle Background CPU",
      "trust.agents": "AI Agents Detected",
      "trust.noRoot": "Standard User Only",
      "bento.kicker": "BENTO MENU BAR PANEL",
      "bento.title": "6 cards. Every vital Mac metric at a glance.",
      "bento.desc": "No cluttered submenus. High-frequency sampling runs only while the popover is open and drops to near-zero when closed. Hover any card to inspect extra details.",
      "bento.cpu.badge": "P/E Core Matrix",
      "bento.cpu.title": "CPU & Process Treemap",
      "bento.cpu.desc": "Total load, P-core / E-core visual load matrix, and a live mini-treemap of top CPU consumers so spikes stand out immediately.",
      "bento.mem.badge": "Pressure & Swap",
      "bento.mem.title": "Activity Monitor-Aligned Memory",
      "bento.mem.desc": "Used and total RAM matching Activity Monitor, paired with memory pressure & swap indicators and top memory-hungry apps.",
      "bento.storage.badge": "R/W Throughput",
      "bento.storage.title": "Categorized Storage Matrix",
      "bento.storage.desc": "Live disk read/write throughput (MB/s) plus a pixel matrix breaking down system, Apps, user, cache, and free space.",
      "bento.network.badge": "Listening Ports",
      "bento.network.title": "Network & Local Services",
      "bento.network.desc": "Live download/upload speeds on your primary interface plus an automatic table of local listening ports (Web, AI, DB, Proxy — node, ollama, etc.).",
      "bento.battery.badge": "USB-C PD & Watts",
      "bento.battery.title": "Battery Health & Live Power",
      "bento.battery.desc": "Charge state, cycle count, 4-cell health matrix, negotiated USB-C PD adapter wattage, and real-time system power draw (W).",
      "bento.thermal.badge": "Thermal & Fan",
      "bento.thermal.title": "Temperatures & Fan RPM",
      "bento.thermal.desc": "Real-time CPU, GPU, and SSD temperature gauges (°C), thermal state badge, fan speed (RPM), and peak temperature tracking.",
      "analyze.kicker": "ANALYZE · DISK & AI AGENT FOOTPRINT",
      "analyze.title": "Streaming squarified treemaps that surface hidden space hogs",
      "analyze.desc": "A pure-Swift squarified treemap engine streaming snapshots every 0.2s—drill into subfolders before the scan even finishes. Automatic checkpoints let you pause, quit, and resume anytime.",
      "analyze.f1.title": "Live Streaming & Resume Cache",
      "analyze.f1.desc": "Scan checkpoints persist automatically to local cache. Close the window or quit Peek anytime and continue right where you left off.",
      "analyze.f2.title": "Semantic Color Categories",
      "analyze.f2.desc": "Automatically classifies Apps, Dev (node_modules, DerivedData, .cargo, etc.), Agents, Media, Docs, and System for instant clarity.",
      "analyze.f3.title": "Stale Downloads Tab",
      "analyze.f3.desc": "Surfaces files and installers in ~/Downloads untouched for over 90 days—reveal in Finder or move safely to Trash in one click.",
      "analyze.agentsTitle": "Dedicated Footprint Tab for 19+ AI Coding Agents & Local Models",
      "analyze.agentsDesc": "Automatically aggregates scattered model weights, caches, and session histories across your home & Library folders:",
      "uninstall.kicker": "UNINSTALL · VISUAL APP UNINSTALLER",
      "uninstall.title": "Sized by footprint, colored by recency, cleaned down to leftovers",
      "uninstall.desc": "Visualizes /Applications and ~/Applications by size and colors every app by Spotlight last-used date (≤7d to >1y), making neglected space hogs impossible to miss.",
      "uninstall.f1.title": "Deep ~/Library Residual Matching",
      "uninstall.f1.desc": "Matches associated data across Application Support, Caches, Preferences, Containers, Saved Application State, Logs, and more via Bundle ID and name.",
      "uninstall.f2.title": "Built-in Safety Guards",
      "uninstall.f2.desc": "Locks system apps and Peek itself from accidental removal; flags running apps with a live badge and prompts you to quit them first.",
      "uninstall.f3.title": "Preview First, Trash Only",
      "uninstall.f3.desc": "Every removal previews every matched path and total reclaimed size first, then moves items to Trash—never silent permanent deletion.",
      "arch.kicker": "NATIVE ARCHITECTURE & PRIVACY",
      "arch.title": "Lightweight by design, completely under your control",
      "arch.p1.title": "Zero-Overhead Background",
      "arch.p1.desc": "High-frequency sampling runs only while the menu bar popover is open and pauses immediately on close.",
      "arch.p2.title": "Graceful Permission Degradation",
      "arch.p2.desc": "Runs as a standard user with no admin password. Full Disk Access is completely optional and degrades cleanly when omitted.",
      "arch.p3.title": "Verified In-App Updater",
      "arch.p3.desc": "Checks GitHub Releases for your Mac's architecture and verifies both SHA-256 checksums and signing certificate fingerprints before updating.",
      "arch.p4.title": "Instant Bilingual Switch",
      "arch.p4.desc": "Switch between English, Simplified Chinese, or System Default live inside Settings without restarting.",
      "install.kicker": "DOWNLOAD & INSTALL",
      "install.title": "Up and running in your menu bar in 30 seconds",
      "install.desc": "Requires macOS 14.0 (Sonoma) or later. Separate native builds for Apple Silicon and Intel Macs.",
      "install.downloadTitle": "Download DMG",
      "install.downloadDesc": "Grab the .dmg matching your Mac's architecture, open it, and drag Peek into your Applications folder.",
      "install.armTitle": "Apple Silicon (M1 / M2 / M3 / M4)",
      "install.intelTitle": "Intel Mac (x86_64)",
      "install.checksums": "View Release Notes & SHA256SUMS ↗",
      "install.fromSource": "Build from Source ↗",
      "install.gatekeeperTitle": "First-Launch Gatekeeper Note",
      "install.gatekeeperDesc": "Peek is signed with a persistent self-signed certificate (so your macOS privacy permissions survive updates) rather than Apple notarization. On first launch, allow it once:",
      "install.step1": "Click <strong>Done</strong> on the macOS security prompt (do not click Move to Trash).",
      "install.step2": "Open <strong>System Settings → Privacy &amp; Security</strong>, scroll to Security, and click <strong>Open Anyway</strong> next to Peek.",
      "install.step3": "Confirm with Touch ID or your password, then launch Peek again.",
      "install.terminalTip": "Or clear quarantine in Terminal:",
      "install.copy": "Copy",
      "install.copied": "Copied",
      "footer.tagline": "Lightweight, native macOS menu bar monitor & analyzer",
      "footer.releases": "Releases",
      "footer.issues": "Issues",
      "footer.origin": "Originally launched on Linux.do · Built with native Swift & SwiftUI"
    }
  };

  let currentLang = detectInitialLang();
  let currentVersion = FALLBACK_VERSION;

  function detectInitialLang() {
    const saved = localStorage.getItem("peek-website-lang");
    if (saved === "zh" || saved === "en") return saved;
    const navLang = (navigator.language || "en").toLowerCase();
    return navLang.startsWith("zh") ? "zh" : "en";
  }

  function applyLanguage(lang) {
    currentLang = lang;
    localStorage.setItem("peek-website-lang", lang);
    document.documentElement.lang = lang === "zh" ? "zh-CN" : "en";

    const dict = I18N[lang];
    document.title = dict.pageTitle;
    const metaDesc = document.querySelector('meta[name="description"]');
    if (metaDesc) metaDesc.setAttribute("content", dict.pageDesc);

    document.querySelectorAll("[data-i18n]").forEach((el) => {
      const key = el.getAttribute("data-i18n");
      if (!key || !(key in dict)) return;
      const value = dict[key].replace("{ver}", currentVersion);
      if (value.includes("<")) {
        el.innerHTML = value;
      } else {
        el.textContent = value;
      }
    });

    document.querySelectorAll("[data-lang-opt]").forEach((el) => {
      el.classList.toggle("active", el.getAttribute("data-lang-opt") === lang);
    });
  }

  function formatBytes(bytes) {
    if (!bytes || Number.isNaN(bytes)) return "";
    const mb = bytes / (1024 * 1024);
    return mb >= 1 ? `${mb.toFixed(1)} MB` : `${Math.round(bytes / 1024)} KB`;
  }

  function applyReleaseData(version, armAsset, x86Asset) {
    currentVersion = version;
    const tag = `v${version}`;

    const navVer = document.getElementById("nav-version");
    if (navVer) navVer.textContent = tag;

    const releaseMeta = document.getElementById("release-meta");
    if (releaseMeta) {
      releaseMeta.textContent = I18N[currentLang]["hero.releaseLoading"].replace("{ver}", version);
    }

    const fallbackArmUrl = `https://github.com/${REPO}/releases/download/${tag}/Peek-${version}-arm64.dmg`;
    const fallbackX86Url = `https://github.com/${REPO}/releases/download/${tag}/Peek-${version}-x86_64.dmg`;

    const armUrl = armAsset?.browser_download_url || fallbackArmUrl;
    const x86Url = x86Asset?.browser_download_url || fallbackX86Url;

    const armSize = armAsset?.size ? ` · ${formatBytes(armAsset.size)}` : "";
    const x86Size = x86Asset?.size ? ` · ${formatBytes(x86Asset.size)}` : "";

    const dlArm = document.getElementById("dl-arm64");
    const dlX86 = document.getElementById("dl-x86");
    const dlArmMeta = document.getElementById("dl-arm64-meta");
    const dlX86Meta = document.getElementById("dl-x86-meta");

    if (dlArm) dlArm.href = armUrl;
    if (dlX86) dlX86.href = x86Url;
    if (dlArmMeta) dlArmMeta.textContent = `arm64 · ${tag}${armSize}`;
    if (dlX86Meta) dlX86Meta.textContent = `x86_64 · ${tag}${x86Size}`;

    const installArm = document.getElementById("install-dl-arm64");
    const installX86 = document.getElementById("install-dl-x86");
    const installArmFile = document.getElementById("install-dl-arm64-file");
    const installX86File = document.getElementById("install-dl-x86-file");

    if (installArm) installArm.href = armUrl;
    if (installX86) installX86.href = x86Url;
    if (installArmFile) installArmFile.textContent = `Peek-${version}-arm64.dmg${armSize}`;
    if (installX86File) installX86File.textContent = `Peek-${version}-x86_64.dmg${x86Size}`;
  }

  async function fetchLatestRelease() {
    applyReleaseData(FALLBACK_VERSION, null, null);
    try {
      const res = await fetch(`https://api.github.com/repos/${REPO}/releases/latest`, {
        headers: { Accept: "application/vnd.github+json" }
      });
      if (!res.ok) return;
      const data = await res.json();
      const rawTag = typeof data.tag_name === "string" ? data.tag_name : "";
      const version = rawTag.replace(/^v/i, "") || FALLBACK_VERSION;
      const assets = Array.isArray(data.assets) ? data.assets : [];
      const armAsset = assets.find((a) => /arm64\.dmg$/i.test(a.name || ""));
      const x86Asset = assets.find((a) => /x86_64\.dmg$/i.test(a.name || ""));
      applyReleaseData(version, armAsset, x86Asset);
    } catch {
      // Keep fallback links silently
    }
  }

  // Copy buttons
  function setupCopyButtons() {
    document.querySelectorAll(".copy-btn").forEach((btn) => {
      btn.addEventListener("click", async () => {
        const text = btn.getAttribute("data-copy") || "";
        try {
          await navigator.clipboard.writeText(text);
          const label = btn.querySelector("span");
          btn.classList.add("copied");
          if (label) label.textContent = I18N[currentLang]["install.copied"];
          setTimeout(() => {
            btn.classList.remove("copied");
            if (label) label.textContent = I18N[currentLang]["install.copy"];
          }, 1800);
        } catch {
          // Fallback selection if clipboard API unavailable
        }
      });
    });
  }

  // Lightbox
  function setupLightbox() {
    const lightbox = document.getElementById("lightbox");
    const img = document.getElementById("lightbox-img");
    const caption = document.getElementById("lightbox-caption");
    const closeBtn = document.getElementById("lightbox-close");
    if (!lightbox || !img || !caption || !closeBtn) return;

    function openLightbox(src, cap) {
      img.src = src;
      img.alt = cap;
      caption.textContent = cap;
      lightbox.classList.add("open");
      lightbox.setAttribute("aria-hidden", "false");
      document.body.style.overflow = "hidden";
    }

    function closeLightbox() {
      lightbox.classList.remove("open");
      lightbox.setAttribute("aria-hidden", "true");
      document.body.style.overflow = "";
    }

    document.querySelectorAll("[data-lightbox]").forEach((trigger) => {
      trigger.addEventListener("click", () => {
        const src = trigger.getAttribute("data-lightbox");
        const cap =
          trigger.getAttribute(currentLang === "zh" ? "data-caption-zh" : "data-caption-en") || "";
        if (src) openLightbox(src, cap);
      });
    });

    closeBtn.addEventListener("click", closeLightbox);
    lightbox.addEventListener("click", (e) => {
      if (e.target === lightbox) closeLightbox();
    });
    document.addEventListener("keydown", (e) => {
      if (e.key === "Escape" && lightbox.classList.contains("open")) {
        closeLightbox();
      }
    });
  }

  // Scroll Reveal
  function setupReveal() {
    const nodes = document.querySelectorAll(".reveal");
    if (!("IntersectionObserver" in window)) {
      nodes.forEach((n) => n.classList.add("is-visible"));
      return;
    }
    const observer = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) {
            entry.target.classList.add("is-visible");
            observer.unobserve(entry.target);
          }
        });
      },
      { threshold: 0.12, rootMargin: "0px 0px -30px 0px" }
    );
    nodes.forEach((n) => observer.observe(n));
  }

  // Init
  document.addEventListener("DOMContentLoaded", () => {
    applyLanguage(currentLang);
    fetchLatestRelease();
    setupCopyButtons();
    setupLightbox();
    setupReveal();

    const toggle = document.getElementById("lang-toggle");
    if (toggle) {
      toggle.addEventListener("click", () => {
        applyLanguage(currentLang === "zh" ? "en" : "zh");
      });
    }
  });
})();
