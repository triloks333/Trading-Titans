/* Trading Titans — site interactions (vanilla, no dependencies) */
(function () {
  "use strict";
  var reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  /* ---- Navbar scrolled state ---- */
  var nav = document.getElementById("nav");
  function onScrollNav() {
    if (window.scrollY > 24) nav.classList.add("scrolled");
    else nav.classList.remove("scrolled");
  }
  onScrollNav();

  /* ---- Mobile menu ---- */
  var menuBtn = document.getElementById("menuBtn");
  var navLinks = document.getElementById("navLinks");
  if (menuBtn) {
    menuBtn.addEventListener("click", function () { navLinks.classList.toggle("open"); });
    navLinks.addEventListener("click", function (e) { if (e.target.tagName === "A") navLinks.classList.remove("open"); });
  }

  /* ---- Seamless marquee (duplicate content once) ---- */
  var mq = document.getElementById("marquee");
  if (mq) { mq.innerHTML += mq.innerHTML; }

  /* ---- Scroll reveal + count-up trigger ---- */
  var reveals = document.querySelectorAll(".reveal");
  if ("IntersectionObserver" in window && !reduce) {
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (en) {
        if (en.isIntersecting) { en.target.classList.add("in"); io.unobserve(en.target); }
      });
    }, { threshold: 0.14, rootMargin: "0px 0px -8% 0px" });
    reveals.forEach(function (el) { io.observe(el); });
  } else {
    reveals.forEach(function (el) { el.classList.add("in"); });
  }

  /* ---- Count-up numbers ---- */
  var counters = document.querySelectorAll("[data-count]");
  function animateCount(el) {
    var target = parseFloat(el.getAttribute("data-count"));
    var suffix = el.getAttribute("data-suffix") || "";
    var prefix = (el.textContent.trim().charAt(0) === "₹") ? "₹" : "";
    if (isNaN(target) || reduce) { return; }
    var start = 0, dur = 1400, t0 = null;
    function tick(ts) {
      if (!t0) t0 = ts;
      var p = Math.min((ts - t0) / dur, 1);
      var eased = 1 - Math.pow(1 - p, 3);
      el.textContent = prefix + Math.round(target * eased) + suffix;
      if (p < 1) requestAnimationFrame(tick);
    }
    requestAnimationFrame(tick);
  }
  if ("IntersectionObserver" in window) {
    var cio = new IntersectionObserver(function (entries) {
      entries.forEach(function (en) { if (en.isIntersecting) { animateCount(en.target); cio.unobserve(en.target); } });
    }, { threshold: 0.6 });
    counters.forEach(function (c) { cio.observe(c); });
  }

  /* ---- FAQ accordion ---- */
  document.querySelectorAll(".qa button").forEach(function (b) {
    b.addEventListener("click", function () {
      var qa = b.parentElement, open = qa.classList.contains("open");
      document.querySelectorAll(".qa").forEach(function (x) { x.classList.remove("open"); });
      if (!open) qa.classList.add("open");
    });
  });

  /* ---- Hero device: cycle screenshots ---- */
  var screen = document.getElementById("heroScreen");
  if (screen) {
    var imgs = screen.querySelectorAll("img"), idx = 0;
    if (imgs.length > 1 && !reduce) {
      setInterval(function () {
        imgs[idx].classList.remove("active");
        idx = (idx + 1) % imgs.length;
        imgs[idx].classList.add("active");
      }, 3000);
    }
  }

  /* ---- Device 3D tilt on pointer ---- */
  var phone = document.getElementById("tiltPhone");
  var stage = document.querySelector(".phone-stage");
  if (phone && stage && !reduce && window.matchMedia("(pointer:fine)").matches) {
    stage.addEventListener("mousemove", function (e) {
      var r = stage.getBoundingClientRect();
      var px = (e.clientX - r.left) / r.width - 0.5;
      var py = (e.clientY - r.top) / r.height - 0.5;
      phone.style.transform = "rotateY(" + (px * 14) + "deg) rotateX(" + (-py * 14) + "deg) translateZ(12px)";
    });
    stage.addEventListener("mouseleave", function () { phone.style.transform = "rotateY(0) rotateX(0)"; });
  }

  /* ---- Magnetic buttons ---- */
  if (!reduce && window.matchMedia("(pointer:fine)").matches) {
    document.querySelectorAll("[data-magnetic]").forEach(function (btn) {
      btn.addEventListener("mousemove", function (e) {
        var r = btn.getBoundingClientRect();
        var mx = e.clientX - r.left - r.width / 2;
        var my = e.clientY - r.top - r.height / 2;
        btn.style.transform = "translate(" + mx * 0.22 + "px," + my * 0.32 + "px)";
      });
      btn.addEventListener("mouseleave", function () { btn.style.transform = ""; });
    });
  }

  /* ---- Parallax: blobs + float cards ---- */
  var blobs = document.querySelectorAll(".blob");
  var floats = document.querySelectorAll(".float-card");
  var ticking = false;
  function parallax() {
    var y = window.scrollY;
    blobs.forEach(function (o, i) { o.style.transform = "translateY(" + (y * (i + 1) * 0.05) + "px)"; });
    floats.forEach(function (f) {
      var d = parseFloat(f.getAttribute("data-depth")) || 16;
      f.style.transform = "translateY(" + (-y * d / 110) + "px)";
    });
    ticking = false;
  }
  function onScroll() { onScrollNav(); if (!ticking && !reduce) { requestAnimationFrame(parallax); ticking = true; } }
  window.addEventListener("scroll", onScroll, { passive: true });

  /* ---- Gallery drag-to-scroll ---- */
  var gallery = document.getElementById("gallery");
  if (gallery) {
    var down = false, startX = 0, startScroll = 0;
    gallery.addEventListener("mousedown", function (e) { down = true; startX = e.pageX; startScroll = gallery.scrollLeft; gallery.style.cursor = "grabbing"; });
    window.addEventListener("mouseup", function () { down = false; gallery.style.cursor = ""; });
    gallery.addEventListener("mouseleave", function () { down = false; });
    gallery.addEventListener("mousemove", function (e) { if (!down) return; e.preventDefault(); gallery.scrollLeft = startScroll - (e.pageX - startX) * 1.4; });
  }
})();
