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
