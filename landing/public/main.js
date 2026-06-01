'use strict';

/* ── NAV SCROLL ── */
const navbar = document.getElementById('navbar');
window.addEventListener('scroll', () => {
  navbar.classList.toggle('scrolled', window.scrollY > 16);
}, { passive: true });

/* ── HAMBURGER ── */
const hamburger = document.getElementById('hamburger');
const mobileMenu = document.getElementById('mobile-menu');
hamburger.addEventListener('click', () => {
  const open = hamburger.classList.toggle('open');
  mobileMenu.classList.toggle('open', open);
});
mobileMenu.querySelectorAll('a').forEach(a => {
  a.addEventListener('click', () => {
    hamburger.classList.remove('open');
    mobileMenu.classList.remove('open');
  });
});

/* ── REVEAL ON SCROLL ── */
const revealEls = document.querySelectorAll('.reveal');
const revealIO = new IntersectionObserver((entries) => {
  entries.forEach(entry => {
    if (!entry.isIntersecting) return;
    entry.target.classList.add('visible');
    revealIO.unobserve(entry.target);
  });
}, { threshold: 0.1, rootMargin: '0px 0px -32px 0px' });

// stagger children of grid containers
document.querySelectorAll('.problem-grid, .features-grid, .pricing-grid, .testi-grid, .stats-grid').forEach(grid => {
  grid.querySelectorAll('.reveal').forEach((el, i) => {
    el.style.transitionDelay = i * 70 + 'ms';
  });
});
revealEls.forEach(el => revealIO.observe(el));

/* ── COUNT-UP STATS ── */
const countEls = document.querySelectorAll('.countup[data-target]');
const countIO = new IntersectionObserver((entries) => {
  entries.forEach(entry => {
    if (!entry.isIntersecting) return;
    const el = entry.target;
    const target = +el.dataset.target;
    const duration = 1600;
    const start = performance.now();
    const ease = t => 1 - Math.pow(1 - t, 3);
    const tick = (now) => {
      const p = Math.min((now - start) / duration, 1);
      el.textContent = Math.round(ease(p) * target).toLocaleString();
      if (p < 1) requestAnimationFrame(tick);
    };
    requestAnimationFrame(tick);
    countIO.unobserve(el);
  });
}, { threshold: 0.5 });
countEls.forEach(el => countIO.observe(el));

/* ── HERO CAROUSEL ── */
(function () {
  const track  = document.getElementById('carousel-track');
  const dotsEl = document.getElementById('carousel-dots');
  const prev   = document.getElementById('carousel-prev');
  const next   = document.getElementById('carousel-next');
  if (!track) return;

  const slides = track.querySelectorAll('.carousel-slide');
  const total  = slides.length;
  let idx      = 0;
  let timer;

  // build dots
  slides.forEach((_, i) => {
    const d = document.createElement('button');
    d.className = 'carousel-dot' + (i === 0 ? ' active' : '');
    d.setAttribute('aria-label', 'Slide ' + (i + 1));
    d.addEventListener('click', () => go(i));
    dotsEl.appendChild(d);
  });

  function go(to) {
    idx = (to + total) % total;
    track.style.transform = `translateX(-${idx * 100}%)`;
    dotsEl.querySelectorAll('.carousel-dot').forEach((d, i) =>
      d.classList.toggle('active', i === idx)
    );
    resetTimer();
  }

  function resetTimer() {
    clearInterval(timer);
    timer = setInterval(() => go(idx + 1), 4000);
  }

  prev.addEventListener('click', () => go(idx - 1));
  next.addEventListener('click', () => go(idx + 1));

  // pause on hover
  track.closest('.hero-carousel').addEventListener('mouseenter', () => clearInterval(timer));
  track.closest('.hero-carousel').addEventListener('mouseleave', resetTimer);

  resetTimer();
})();

/* ── FAQ ACCORDION ── */
document.querySelectorAll('.faq-q').forEach(btn => {
  btn.addEventListener('click', () => {
    const expanded = btn.getAttribute('aria-expanded') === 'true';
    // close all
    document.querySelectorAll('.faq-q').forEach(b => {
      b.setAttribute('aria-expanded', 'false');
      b.nextElementSibling.classList.remove('open');
    });
    if (!expanded) {
      btn.setAttribute('aria-expanded', 'true');
      btn.nextElementSibling.classList.add('open');
    }
  });
});

/* ── CTA EMAIL VALIDATION ── */
const fctaInput = document.querySelector('.fcta-input');
const fctaBtn   = document.querySelector('.fcta-btn');
if (fctaInput && fctaBtn) {
  fctaBtn.addEventListener('click', () => {
    const val = fctaInput.value.trim();
    const valid = /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(val);
    if (!valid) {
      fctaInput.style.borderColor = '#ef4444';
      fctaInput.focus();
      setTimeout(() => { fctaInput.style.borderColor = ''; }, 2000);
      return;
    }
    fctaBtn.textContent = "You're on the list!";
    fctaBtn.style.opacity = '.75';
    fctaBtn.disabled = true;
    fctaInput.disabled = true;
    fctaInput.placeholder = 'Check your inbox!';
    fctaInput.value = '';
  });
}

/* ── ACTIVE NAV LINK ── */
const sections = document.querySelectorAll('section[id]');
const navLinks = document.querySelectorAll('.nav-links a');
const activeIO = new IntersectionObserver((entries) => {
  entries.forEach(entry => {
    if (entry.isIntersecting) {
      const id = entry.target.id;
      navLinks.forEach(a => {
        const on = a.getAttribute('href') === '#' + id;
        a.style.color = on ? 'var(--text)' : '';
        a.style.background = on ? 'var(--navy-50)' : '';
      });
    }
  });
}, { threshold: 0.4 });
sections.forEach(s => activeIO.observe(s));

/* ── LIGHTBOX ── */
const lightbox     = document.getElementById('lightbox');
const lightboxImg  = document.getElementById('lightbox-img');
const lightboxClose = document.getElementById('lightbox-close');

function openLightbox(src, alt) {
  lightboxImg.src = src;
  lightboxImg.alt = alt;
  lightbox.classList.add('open');
  document.body.style.overflow = 'hidden';
}
function closeLightbox() {
  lightbox.classList.remove('open');
  document.body.style.overflow = '';
  lightboxImg.src = '';
}

document.querySelectorAll('.zoomable').forEach(img => {
  img.addEventListener('click', () => openLightbox(img.src, img.alt));
});
lightboxClose.addEventListener('click', closeLightbox);
lightbox.addEventListener('click', e => { if (e.target === lightbox) closeLightbox(); });
document.addEventListener('keydown', e => { if (e.key === 'Escape') closeLightbox(); });

