(() => {
  "use strict";

  document.documentElement.classList.add("js");
  const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");

  // A line arrives only when its paragraph enters the page.
  const reveals = document.querySelectorAll(".reveal");
  const paragraphs = document.querySelectorAll(".story-paragraph");
  document.querySelectorAll(".feature-card, .person").forEach((item, index) => {
    item.style.transitionDelay = `${(index % 3) * 100}ms`;
  });
  if ("IntersectionObserver" in window) {
    const revealObserver = new IntersectionObserver((entries, observer) => {
      entries.forEach((entry) => {
        if (!entry.isIntersecting) return;
        entry.target.classList.add("is-visible");
        observer.unobserve(entry.target);
      });
    }, { threshold: 0.1, rootMargin: "0px 0px -35px 0px" });
    reveals.forEach((element) => revealObserver.observe(element));

    const storyObserver = new IntersectionObserver((entries, observer) => {
      entries.forEach((entry) => {
        if (!entry.isIntersecting) return;
        entry.target.querySelectorAll(".story-line").forEach((line, index) => {
          line.style.transitionDelay = `${index * 115}ms`;
          line.classList.add("is-visible");
        });
        observer.unobserve(entry.target);
      });
    }, { threshold: 0.12, rootMargin: "0px 0px -50px 0px" });
    paragraphs.forEach((paragraph) => storyObserver.observe(paragraph));
  } else {
    reveals.forEach((element) => element.classList.add("is-visible"));
    document.querySelectorAll(".story-line").forEach((line) => line.classList.add("is-visible"));
  }

  const hero = document.querySelector(".hero");
  let parallaxQueued = false;
  function updateParallax() {
    parallaxQueued = false;
    if (reducedMotion.matches) {
      hero.style.removeProperty("--hero-shift");
      return;
    }
    const amount = Math.min(Math.max(window.scrollY, 0) * 0.17, 110);
    hero.style.setProperty("--hero-shift", `${amount.toFixed(1)}px`);
  }
  window.addEventListener("scroll", () => {
    if (parallaxQueued || window.scrollY > hero.offsetHeight + 150) return;
    parallaxQueued = true;
    requestAnimationFrame(updateParallax);
  }, { passive: true });
  updateParallax();

  const motesCanvas = document.getElementById("motes-canvas");
  const fireCanvas = document.getElementById("fireworks-canvas");
  const motesContext = motesCanvas.getContext("2d");
  const fireContext = fireCanvas.getContext("2d");
  const scenes = [
    { canvas: motesCanvas, context: motesContext, visible: false, width: 0, height: 0 },
    { canvas: fireCanvas, context: fireContext, visible: false, width: 0, height: 0 }
  ];
  const motes = [];
  const sparks = [];
  let fireTimer = 600;
  let frameId = 0;
  let lastTime = 0;

  function resizeScene(scene) {
    const rect = scene.canvas.getBoundingClientRect();
    const ratio = Math.min(window.devicePixelRatio || 1, 2);
    scene.width = rect.width;
    scene.height = rect.height;
    scene.canvas.width = Math.max(1, Math.round(rect.width * ratio));
    scene.canvas.height = Math.max(1, Math.round(rect.height * ratio));
    scene.context.setTransform(ratio, 0, 0, ratio, 0, 0);
  }

  function makeMote(randomPosition = true) {
    const colors = ["255,250,240", "255,227,157", "255,186,172"];
    return {
      x: Math.random() * scenes[0].width,
      y: randomPosition ? Math.random() * scenes[0].height : scenes[0].height + 10,
      speed: 7 + Math.random() * 16,
      drift: (Math.random() - .5) * 13,
      radius: .8 + Math.random() * 2.4,
      phase: Math.random() * Math.PI * 2,
      color: colors[Math.floor(Math.random() * colors.length)]
    };
  }

  function drawMotes(delta, time) {
    const scene = scenes[0];
    const ctx = scene.context;
    ctx.clearRect(0, 0, scene.width, scene.height);
    if (!motes.length) for (let i = 0; i < 40; i += 1) motes.push(makeMote());
    const seconds = delta / 1000;
    motes.forEach((mote, index) => {
      mote.x += (mote.drift + Math.sin(time / 2100 + mote.phase) * 3) * seconds;
      mote.y -= mote.speed * seconds;
      if (mote.y < -15 || mote.x < -20 || mote.x > scene.width + 20) {
        motes[index] = makeMote(false);
        return;
      }
      const alpha = .25 + (Math.sin(time / 900 + mote.phase) + 1) * .16;
      ctx.fillStyle = `rgba(${mote.color},${alpha})`;
      ctx.beginPath();
      ctx.ellipse(mote.x, mote.y, mote.radius, mote.radius * 1.45, -.4, 0, Math.PI * 2);
      ctx.fill();
    });
  }

  function burst() {
    const scene = scenes[1];
    const x = scene.width * (.48 + Math.random() * .4);
    const y = scene.height * (.09 + Math.random() * .27);
    const colors = ["255,212,143", "255,169,149", "159,216,242"];
    const color = colors[Math.floor(Math.random() * colors.length)];
    for (let i = 0; i < 28; i += 1) {
      const angle = (Math.PI * 2 * i) / 28 + Math.random() * .12;
      const speed = 28 + Math.random() * 42;
      sparks.push({
        x, y, vx: Math.cos(angle) * speed, vy: Math.sin(angle) * speed,
        age: 0, life: 850 + Math.random() * 600, color, size: 1 + Math.random() * 1.4
      });
    }
  }

  function drawFireworks(delta) {
    const scene = scenes[1];
    const ctx = scene.context;
    ctx.clearRect(0, 0, scene.width, scene.height);
    fireTimer += delta;
    if (fireTimer > 2300) {
      burst();
      fireTimer = 0;
    }
    const seconds = delta / 1000;
    for (let i = sparks.length - 1; i >= 0; i -= 1) {
      const spark = sparks[i];
      spark.age += delta;
      if (spark.age >= spark.life) { sparks.splice(i, 1); continue; }
      spark.x += spark.vx * seconds;
      spark.y += spark.vy * seconds;
      spark.vy += 27 * seconds;
      ctx.fillStyle = `rgba(${spark.color},${(1 - spark.age / spark.life) * .85})`;
      ctx.beginPath();
      ctx.arc(spark.x, spark.y, spark.size, 0, Math.PI * 2);
      ctx.fill();
    }
  }

  function canAnimate(scene) {
    return scene.visible && !document.hidden && !reducedMotion.matches;
  }
  function tick(time) {
    frameId = 0;
    const delta = lastTime ? Math.min(time - lastTime, 40) : 16;
    lastTime = time;
    if (canAnimate(scenes[0])) drawMotes(delta, time);
    if (canAnimate(scenes[1])) drawFireworks(delta);
    if (scenes.some(canAnimate)) frameId = requestAnimationFrame(tick);
    else lastTime = 0;
  }
  function syncAnimation() {
    if (scenes.some(canAnimate)) {
      if (!frameId) { lastTime = 0; frameId = requestAnimationFrame(tick); }
    } else {
      if (frameId) cancelAnimationFrame(frameId);
      frameId = 0;
      lastTime = 0;
      scenes.forEach((scene) => scene.context.clearRect(0, 0, scene.width, scene.height));
    }
  }
  scenes.forEach(resizeScene);
  if ("ResizeObserver" in window) {
    const resizeObserver = new ResizeObserver((entries) => {
      entries.forEach((entry) => {
        const scene = scenes.find((item) => item.canvas === entry.target);
        if (scene) resizeScene(scene);
      });
    });
    scenes.forEach((scene) => resizeObserver.observe(scene.canvas));
  } else {
    window.addEventListener("resize", () => scenes.forEach(resizeScene));
  }
  if ("IntersectionObserver" in window) {
    const canvasObserver = new IntersectionObserver((entries) => {
      entries.forEach((entry) => {
        const scene = scenes.find((item) => item.canvas === entry.target);
        if (scene) scene.visible = entry.isIntersecting;
      });
      syncAnimation();
    }, { threshold: .01 });
    scenes.forEach((scene) => canvasObserver.observe(scene.canvas));
  } else {
    scenes.forEach((scene) => { scene.visible = true; });
    syncAnimation();
  }
  document.addEventListener("visibilitychange", syncAnimation);
  reducedMotion.addEventListener("change", () => { updateParallax(); syncAnimation(); });

  const form = document.getElementById("subscribe-form");
  const emailInput = document.getElementById("email");
  const status = document.getElementById("form-status");
  const confetti = document.getElementById("confetti");
  const storageKey = "harumachi-coming-soon-email";
  try {
    const savedEmail = localStorage.getItem(storageKey);
    if (savedEmail) emailInput.value = savedEmail;
  } catch (_) { /* File URLs can disable storage in some browsers. */ }

  function popPetals() {
    if (reducedMotion.matches) return;
    const colors = ["#d8453a", "#f3a44b", "#9fd8f2", "#e6aeab"];
    for (let i = 0; i < 13; i += 1) {
      const petal = document.createElement("span");
      const angle = (Math.PI * 2 * i) / 13;
      const distance = 70 + Math.random() * 100;
      petal.style.setProperty("--dx", `${Math.cos(angle) * distance}px`);
      petal.style.setProperty("--dy", `${Math.sin(angle) * distance - 25}px`);
      petal.style.setProperty("--rotate", `${Math.random() * 150}deg`);
      petal.style.setProperty("--petal-color", colors[i % colors.length]);
      confetti.appendChild(petal);
      setTimeout(() => petal.remove(), 1500);
    }
  }

  form.addEventListener("submit", (event) => {
    event.preventDefault();
    const email = emailInput.value.trim();
    emailInput.value = email;
    if (!emailInput.checkValidity()) {
      status.textContent = "请填写有效的邮箱地址。";
      emailInput.focus();
      return;
    }
    try {
      localStorage.setItem(storageKey, email);
      status.textContent = "记下了！邮箱只保存在这个浏览器里。";
      popPetals();
    } catch (_) {
      status.textContent = "浏览器未允许本地保存，请检查隐私设置后再试。";
    }
  });
})();
