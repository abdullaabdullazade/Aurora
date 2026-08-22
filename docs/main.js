const header = document.querySelector('[data-header]');

const updateHeader = () => header?.classList.toggle('scrolled', window.scrollY > 24);
updateHeader();
window.addEventListener('scroll', updateHeader, { passive: true });

const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
const reveals = document.querySelectorAll('.reveal');

if (reducedMotion || !('IntersectionObserver' in window)) {
  reveals.forEach((element) => element.classList.add('visible'));
} else {
  const observer = new IntersectionObserver((entries) => {
    entries.forEach((entry) => {
      if (!entry.isIntersecting) return;
      entry.target.classList.add('visible');
      observer.unobserve(entry.target);
    });
  }, { threshold: 0.12 });

  reveals.forEach((element) => observer.observe(element));
}

const revealHashTarget = () => {
  if (!window.location.hash) return;
  const target = document.querySelector(window.location.hash);
  if (!target) return;
  target.classList.add('visible');
  target.querySelectorAll('.reveal').forEach((element) => element.classList.add('visible'));
};

revealHashTarget();
window.addEventListener('hashchange', revealHashTarget);

const releaseApi = 'https://api.github.com/repos/abdullaabdullazade/Aurora/releases/latest';

const formatBytes = (bytes) => {
  if (!Number.isFinite(bytes)) return null;
  return `${(bytes / 1024 / 1024).toFixed(1)} MB`;
};

fetch(releaseApi, { headers: { Accept: 'application/vnd.github+json' } })
  .then((response) => {
    if (!response.ok) throw new Error(`GitHub API returned ${response.status}`);
    return response.json();
  })
  .then((release) => {
    const apk = release.assets?.find((asset) => asset.name === 'Aurora-Music.apk');
    const published = release.published_at
      ? new Intl.DateTimeFormat('en', { day: 'numeric', month: 'short', year: 'numeric' }).format(new Date(release.published_at))
      : null;

    document.querySelectorAll('[data-release-version]').forEach((element) => {
      element.textContent = release.tag_name;
    });
    if (apk) document.querySelector('[data-release-size]').textContent = formatBytes(apk.size);
    if (published) document.querySelector('[data-release-date]').textContent = published;
  })
  .catch(() => {
    // The static values remain usable if GitHub is offline or rate-limited.
  });

const filterButtons = [...document.querySelectorAll('[data-filter]')];
const galleryCards = [...document.querySelectorAll('.gallery-card')];

filterButtons.forEach((button) => {
  button.addEventListener('click', () => {
    const filter = button.dataset.filter;
    filterButtons.forEach((item) => {
      const active = item === button;
      item.classList.toggle('active', active);
      item.setAttribute('aria-pressed', String(active));
    });

    galleryCards.forEach((card) => {
      card.hidden = filter !== 'all' && card.dataset.category !== filter;
    });
  });
});

const lightbox = document.querySelector('[data-lightbox]');
const lightboxImage = document.querySelector('[data-lightbox-image]');
const lightboxTitle = document.querySelector('[data-lightbox-title]');
const lightboxCategory = document.querySelector('[data-lightbox-category]');
const lightboxCount = document.querySelector('[data-lightbox-count]');
let activeGalleryIndex = 0;

const visibleCards = () => galleryCards.filter((card) => !card.hidden);

const showGalleryCard = (card) => {
  const cards = visibleCards();
  activeGalleryIndex = cards.indexOf(card);
  const source = card.querySelector('img');
  lightboxImage.src = source.src;
  lightboxImage.alt = source.alt;
  lightboxTitle.textContent = card.querySelector('figcaption strong').textContent;
  lightboxCategory.textContent = card.querySelector('figcaption small').textContent;
  lightboxCount.textContent = `${activeGalleryIndex + 1} / ${cards.length}`;
};

const moveGallery = (direction) => {
  const cards = visibleCards();
  activeGalleryIndex = (activeGalleryIndex + direction + cards.length) % cards.length;
  showGalleryCard(cards[activeGalleryIndex]);
};

galleryCards.forEach((card) => {
  card.querySelector('[data-gallery-open]').addEventListener('click', () => {
    showGalleryCard(card);
    lightbox.showModal();
  });
});

document.querySelector('[data-lightbox-close]').addEventListener('click', () => lightbox.close());
document.querySelector('[data-lightbox-prev]').addEventListener('click', () => moveGallery(-1));
document.querySelector('[data-lightbox-next]').addEventListener('click', () => moveGallery(1));
lightbox.addEventListener('click', (event) => {
  if (event.target === lightbox) lightbox.close();
});
lightbox.addEventListener('keydown', (event) => {
  if (event.key === 'ArrowLeft') moveGallery(-1);
  if (event.key === 'ArrowRight') moveGallery(1);
});

if (!reducedMotion && matchMedia('(pointer: fine)').matches) {
  const heroVisual = document.querySelector('.hero-visual');
  heroVisual.addEventListener('pointermove', (event) => {
    const bounds = heroVisual.getBoundingClientRect();
    const x = (event.clientX - bounds.left) / bounds.width - 0.5;
    const y = (event.clientY - bounds.top) / bounds.height - 0.5;
    heroVisual.style.transform = `perspective(900px) rotateY(${x * 3}deg) rotateX(${y * -3}deg)`;
  });
  heroVisual.addEventListener('pointerleave', () => {
    heroVisual.style.transform = '';
  });
}
