// Small synthesized sounds for the stage: no files, nothing to download.

let ctx: AudioContext | undefined;
let enabled = (() => {
  try {
    return localStorage.getItem("skittles-sound") !== "off";
  } catch {
    return true;
  }
})();

export const soundOn = (): boolean => enabled;

export function setSound(on: boolean): void {
  enabled = on;
  try {
    localStorage.setItem("skittles-sound", on ? "on" : "off");
  } catch {
    // A convenience only.
  }
}

function tone(freq: number, start: number, length: number, type: OscillatorType, gain: number, slideTo?: number): void {
  if (!ctx) return;
  const osc = ctx.createOscillator();
  const amp = ctx.createGain();
  osc.type = type;
  osc.frequency.setValueAtTime(freq, ctx.currentTime + start);
  if (slideTo) osc.frequency.exponentialRampToValueAtTime(slideTo, ctx.currentTime + start + length);
  amp.gain.setValueAtTime(0.0001, ctx.currentTime + start);
  amp.gain.exponentialRampToValueAtTime(gain, ctx.currentTime + start + 0.01);
  amp.gain.exponentialRampToValueAtTime(0.0001, ctx.currentTime + start + length);
  osc.connect(amp).connect(ctx.destination);
  osc.start(ctx.currentTime + start);
  osc.stop(ctx.currentTime + start + length + 0.02);
}

export type Sound = "build" | "blocked" | "fix" | "fall" | "win" | "report";

export function play(sound: Sound): void {
  if (!enabled) return;
  ctx ??= new AudioContext();
  if (ctx.state === "suspended") void ctx.resume();
  switch (sound) {
    case "build":
      tone(520, 0, 0.09, "sine", 0.18, 880);
      tone(880, 0.06, 0.08, "sine", 0.1);
      break;
    case "blocked":
      tone(180, 0, 0.28, "sawtooth", 0.12, 90);
      tone(140, 0.12, 0.3, "square", 0.06, 70);
      break;
    case "fix":
      tone(784, 0, 0.14, "triangle", 0.16);
      tone(1175, 0.1, 0.22, "triangle", 0.14);
      break;
    case "fall":
      tone(600, 0, 0.35, "sawtooth", 0.08, 80);
      break;
    case "win":
      [523, 659, 784, 1047].forEach((f, i) => tone(f, i * 0.09, 0.2, "triangle", 0.14));
      break;
    case "report":
      tone(660, 0, 0.1, "sine", 0.14);
      tone(660, 0.14, 0.1, "sine", 0.14);
      break;
  }
}
