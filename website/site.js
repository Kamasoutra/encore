// Copy button, sound toggle and remembered language. Everything works without it.
document.querySelectorAll("[data-copy]").forEach(button => {
  const label = button.textContent;
  button.addEventListener("click", async () => {
    try { await navigator.clipboard.writeText(button.dataset.copy); } catch (e) { return; }
    button.textContent = button.dataset.done;
    setTimeout(() => { button.textContent = label; }, 1600);
  });
});
document.querySelectorAll(".film").forEach(film => {
  const video = film.querySelector("video"), button = film.querySelector(".sound");
  button.addEventListener("click", () => {
    video.muted = !video.muted;
    if (!video.muted) { video.currentTime = 0; video.play(); }
    button.textContent = video.muted ? button.dataset.on : button.dataset.off;
  });
});
document.querySelectorAll("[data-lang]").forEach(link => {
  link.addEventListener("click", () => { try { localStorage.setItem("lang", link.dataset.lang); } catch (e) {} });
});

// Changelog: the version being read is highlighted in the list, which follows on narrow screens.
const versions = document.querySelectorAll(".changes nav a");
if (versions.length && "IntersectionObserver" in window) {
  const links = new Map([...versions].map(a => [a.getAttribute("href").slice(1), a]));
  const observer = new IntersectionObserver(entries => entries.forEach(entry => {
    if (!entry.isIntersecting) return;
    versions.forEach(a => a.classList.remove("on"));
    const link = links.get(entry.target.id);
    if (link) { link.classList.add("on"); link.parentElement.parentElement.scrollLeft = link.offsetLeft - 16; }
  }), { rootMargin: "-30% 0px -60% 0px" });
  document.querySelectorAll(".release").forEach(release => observer.observe(release));
}

// Changelog filters: only one kind of change, or all of them.
document.querySelectorAll(".filters button").forEach(button => button.addEventListener("click", () => {
  const log = document.querySelector(".log");
  document.querySelectorAll(".filters button").forEach(b => b.classList.toggle("on", b === button));
  if (button.dataset.kind) log.dataset.only = button.dataset.kind; else delete log.dataset.only;
}));
