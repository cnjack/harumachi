(() => {
  "use strict";

  const pageTabs = [...document.querySelectorAll(".page-tabs [role=tab]")];
  const panels = [...document.querySelectorAll("main > [role=tabpanel]")];
  const audio = document.getElementById("soundtrack-player");
  const grid = document.getElementById("wallpaper-grid");
  const tracklist = document.getElementById("tracklist");
  const message = document.getElementById("player-message");
  let library;
  let loading;
  let device = window.matchMedia("(max-width: 700px)").matches ? "mobile" : "desktop";
  let currentTrack = null;

  const element = (tag, className, text) => {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (text) node.textContent = text;
    return node;
  };
  const time = (seconds) => `${Math.floor(seconds / 60)}:${String(Math.floor(seconds % 60)).padStart(2, "0")}`;

  function musicLoading(waiting) {
    message.dataset.state = waiting ? "loading" : "";
    message.textContent = waiting ? "音乐缓冲中，请稍候……" : "";
    audio.setAttribute("aria-busy", String(waiting));
  }

  function renderWallpapers() {
    document.querySelectorAll(".device-switch button").forEach((button) => {
      button.setAttribute("aria-pressed", String(button.dataset.device === device));
    });
    grid.replaceChildren();
    grid.classList.toggle("portrait-grid", device === "mobile");
    const items = library.wallpapers.filter((item) => item.device === device);
    document.getElementById("wallpaper-count").textContent = `${items.length} 张 · ${device === "mobile" ? "手机竖版" : "电脑横版"}`;
    items.forEach((item, index) => {
      const card = element("article", "wallpaper-card");
      const picture = element("div", "wallpaper-picture");
      picture.classList.add("is-loading");
      picture.setAttribute("aria-busy", "true");
      const loader = element("span", "media-loader");
      loader.setAttribute("aria-hidden", "true");
      picture.append(loader);
      const image = element("img");
      image.addEventListener("load", () => {
        picture.classList.remove("is-loading");
        picture.setAttribute("aria-busy", "false");
      });
      image.addEventListener("error", () => {
        picture.classList.remove("is-loading");
        picture.classList.add("is-error");
        picture.setAttribute("aria-busy", "false");
        loader.textContent = "预览暂时无法加载，可下载原图。";
        loader.removeAttribute("aria-hidden");
      });
      image.src = item.preview;
      image.width = item.width;
      image.height = item.height;
      image.alt = `${item.title}，${device === "mobile" ? "手机竖版" : "电脑横版"}壁纸`;
      image.loading = "lazy";
      picture.append(image);
      const number = element("span", "wallpaper-number", `0${index + 1}`);
      picture.append(number);
      const body = element("div", "wallpaper-card-body");
      body.append(element("h2", "", item.title));
      body.append(element("p", "wallpaper-meta", `${item.width} × ${item.height} · JPG · ${(item.bytes / 1024 / 1024).toFixed(1)} MB`));
      const download = element("a", "wallpaper-download", "下载壁纸 ↓");
      download.href = item.src;
      download.download = `harumachi-${item.id}.jpg`;
      download.setAttribute("aria-label", `下载${item.title}${device === "mobile" ? "手机" : "电脑"}壁纸`);
      body.append(download);
      card.append(picture, body);
      grid.append(card);
    });
  }

  function syncTrackState() {
    document.getElementById("player-caption").textContent = currentTrack ? (audio.paused ? "已暂停" : "正在聆听") : "游戏配乐";
    tracklist.querySelectorAll(".track-play").forEach((button) => {
      const active = button.dataset.track === currentTrack?.id;
      const playing = active && !audio.paused;
      button.textContent = playing ? "Ⅱ" : "▶";
      button.setAttribute("aria-label", `${playing ? "暂停" : "播放"}《${button.dataset.title}》`);
      button.closest("li").classList.toggle("is-current", active);
      button.closest("li").classList.toggle("is-playing", playing);
    });
  }

  async function playTrack(track) {
    if (currentTrack?.id === track.id && !audio.paused) {
      audio.pause();
      return;
    }
    if (currentTrack?.id !== track.id) {
      currentTrack = track;
      audio.src = track.src;
      audio.hidden = false;
      document.getElementById("now-playing-title").textContent = track.title;
      document.getElementById("now-playing-context").textContent = track.context;
      const mp3 = document.getElementById("current-mp3");
      const ogg = document.getElementById("current-ogg");
      mp3.href = track.src;
      mp3.download = `harumachi-${track.id}.mp3`;
      ogg.href = track.original;
      ogg.download = `harumachi-${track.id}.ogg`;
      document.getElementById("player-links").hidden = false;
    }
    musicLoading(true);
    syncTrackState();
    try {
      await audio.play();
    } catch (error) {
      musicLoading(false);
      if (error.name === "AbortError") return;
      message.textContent = "暂时无法播放，请再点一次播放，或下载音乐收听。";
    }
  }

  function renderTracks() {
    const total = library.tracks.reduce((seconds, track) => seconds + track.duration, 0);
    document.getElementById("track-summary").textContent = `${library.tracks.length} 首 · ${Math.round(total / 60)} 分钟`;
    library.tracks.forEach((track, index) => {
      const row = element("li", "track-row");
      row.append(element("span", "track-number", String(index + 1).padStart(2, "0")));
      const play = element("button", "track-play", "▶");
      play.type = "button";
      play.dataset.track = track.id;
      play.dataset.title = track.title;
      play.setAttribute("aria-label", `播放《${track.title}》`);
      play.addEventListener("click", () => playTrack(track));
      const info = element("div", "track-info");
      info.append(element("h3", "", track.title), element("p", "", track.context));
      const duration = element("span", "track-duration", time(track.duration));
      const download = element("a", "track-download", "↓");
      download.href = track.src;
      download.download = `harumachi-${track.id}.mp3`;
      download.setAttribute("aria-label", `下载《${track.title}》MP3`);
      row.append(play, info, duration, download);
      tracklist.append(row);
    });
  }

  function loadLibrary() {
    if (library) return Promise.resolve();
    if (loading) return loading;
    ["wallpaper-status", "music-status"].forEach((id) => {
      document.getElementById(id).textContent = "正在打开晴町收藏……";
      document.getElementById(id).dataset.state = "loading";
    });
    loading = fetch("assets/library.json", { cache: "no-cache" })
      .then((response) => {
        if (!response.ok) throw new Error("Library unavailable");
        return response.json();
      })
      .then((data) => {
        library = data;
        renderWallpapers();
        renderTracks();
        ["wallpaper-status", "music-status"].forEach((id) => {
          document.getElementById(id).textContent = "";
          document.getElementById(id).dataset.state = "";
        });
      })
      .catch(() => {
        loading = null;
        ["wallpaper-status", "music-status"].forEach((id) => {
          document.getElementById(id).textContent = "暂时没有加载成功，请切换页签再试一次。";
          document.getElementById(id).dataset.state = "error";
        });
      });
    return loading;
  }

  function activatePage(page, updateHash = false) {
    pageTabs.forEach((tab) => {
      const active = tab.dataset.page === page;
      tab.setAttribute("aria-selected", String(active));
      tab.tabIndex = active ? 0 : -1;
    });
    panels.forEach((panel) => { panel.hidden = panel.id !== `panel-${page}`; });
    document.body.classList.toggle("is-library", page !== "home");
    if (page !== "music") audio.pause();
    if (page === "music" || page === "wallpapers") loadLibrary();
    if (updateHash) {
      const hash = page === "home" ? "#top" : `#${page}`;
      if (location.hash !== hash) history.pushState(null, "", hash);
      window.scrollTo({ top: 0, behavior: "instant" });
    }
  }

  function pageFromHash() {
    const page = location.hash.slice(1);
    if (page === "main") return pageTabs.find((tab) => tab.getAttribute("aria-selected") === "true")?.dataset.page || "home";
    return ["wallpapers", "music", "play"].includes(page) ? page : "home";
  }
  pageTabs.forEach((tab, index) => {
    tab.addEventListener("click", () => activatePage(tab.dataset.page, true));
    tab.addEventListener("keydown", (event) => {
      let next;
      if (event.key === "ArrowRight") next = (index + 1) % pageTabs.length;
      if (event.key === "ArrowLeft") next = (index + pageTabs.length - 1) % pageTabs.length;
      if (event.key === "Home") next = 0;
      if (event.key === "End") next = pageTabs.length - 1;
      if (next === undefined) return;
      event.preventDefault();
      pageTabs[next].focus();
      activatePage(pageTabs[next].dataset.page, true);
    });
  });
  document.querySelectorAll(".device-switch button").forEach((button) => {
    button.addEventListener("click", () => {
      device = button.dataset.device;
      document.querySelectorAll(".device-switch button").forEach((other) => {
        other.setAttribute("aria-pressed", String(other === button));
      });
      if (library) renderWallpapers();
    });
  });
  ["play", "pause", "ended"].forEach((event) => audio.addEventListener(event, syncTrackState));
  ["loadstart", "waiting", "stalled"].forEach((event) => audio.addEventListener(event, () => { if (!audio.paused) musicLoading(true); }));
  ["playing", "canplay", "pause", "ended"].forEach((event) => audio.addEventListener(event, () => musicLoading(false)));
  audio.addEventListener("error", () => { musicLoading(false); message.textContent = "这首音乐暂时无法加载，请稍后重试。"; });
  window.addEventListener("hashchange", () => activatePage(pageFromHash()));
  window.addEventListener("popstate", () => activatePage(pageFromHash()));
  activatePage(pageFromHash());
})();
