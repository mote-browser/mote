// Follows a pinned scene's scroll: the opening story, or any .scene. Its
// progress through its tall wrapper runs from 0 to 1. Where CSS can't tie
// animations to the scroll by itself (Firefox, for now), the progress goes
// into --p on the stage and the stylesheets scrub the animations with it.
// `onProgress` is for anything else that needs to know, like the story
// filling in its sidebar.

export function follow(wrapper: HTMLElement, onProgress?: (progress: number) => void) {
  const mode = document.documentElement.dataset.story;
  if (!mode) return;
  const stage = wrapper.firstElementChild as HTMLElement;
  let top = 0;
  let span = 1;
  let queued = false;

  const update = () => {
    queued = false;
    const progress = Math.min(1, Math.max(0, (scrollY - top) / span));
    if (mode === "scripted") stage.style.setProperty("--p", progress.toFixed(4));
    onProgress?.(progress);
  };

  // Layout is read here only, never while scrolling.
  const measure = () => {
    top = wrapper.getBoundingClientRect().top + scrollY;
    span = Math.max(1, wrapper.offsetHeight - innerHeight);
    update();
  };

  addEventListener(
    "scroll",
    () => {
      if (queued) return;
      queued = true;
      requestAnimationFrame(update);
    },
    { passive: true },
  );
  addEventListener("resize", measure);
  document.fonts.ready.then(measure);
  measure();
}
