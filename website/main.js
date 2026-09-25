// FastTrack website — small, dependency-free progressive enhancement.

// Where the download buttons point. Edit these when you publish a build.
const DOWNLOADS = {
  // Attach `fasttrack.apk` to a GitHub Release and this link always serves the latest one.
  android: 'https://github.com/adeyanjufuhad/FastTrack/releases/latest/download/fasttrack.apk',
  // The Flutter web build is deployed next to this site under /app/ (see website/README.md).
  web: 'app/',
};

document.documentElement.classList.add('js');

for (const a of document.querySelectorAll('[data-dl]')) {
  const url = DOWNLOADS[a.dataset.dl];
  if (url) a.href = url;
  if (a.dataset.dl === 'android') a.setAttribute('download', 'fasttrack.apk');
}

// Sticky nav shadow
const nav = document.querySelector('.nav');
const onScroll = () => nav.classList.toggle('is-scrolled', window.scrollY > 8);
onScroll();
window.addEventListener('scroll', onScroll, { passive: true });

// Mobile menu
const toggle = document.querySelector('.nav__toggle');
const links = document.getElementById('nav-links');
const setMenu = (open) => {
  toggle.setAttribute('aria-expanded', String(open));
  toggle.setAttribute('aria-label', open ? 'Close menu' : 'Open menu');
  links.classList.toggle('is-open', open);
};
toggle.addEventListener('click', () => setMenu(toggle.getAttribute('aria-expanded') !== 'true'));
links.addEventListener('click', (e) => { if (e.target.closest('a')) setMenu(false); });
document.addEventListener('keydown', (e) => { if (e.key === 'Escape') setMenu(false); });
window.matchMedia('(min-width: 861px)').addEventListener('change', (m) => { if (m.matches) setMenu(false); });

// Reveal on scroll
const revealed = document.querySelectorAll('.reveal');
if ('IntersectionObserver' in window) {
  const io = new IntersectionObserver((entries) => {
    for (const en of entries) {
      if (en.isIntersecting) {
        en.target.classList.add('is-in');
        io.unobserve(en.target);
      }
    }
  }, { rootMargin: '0px 0px -8% 0px', threshold: 0.08 });
  revealed.forEach((el) => io.observe(el));
} else {
  revealed.forEach((el) => el.classList.add('is-in'));
}

document.getElementById('year').textContent = String(new Date().getFullYear());
