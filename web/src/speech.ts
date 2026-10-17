// Voice input through the browser's speech recognition (Chrome and Edge; Georgian included).

import { useCallback, useEffect, useRef, useState } from "react";

type Recognition = {
  lang: string;
  interimResults: boolean;
  continuous: boolean;
  onresult: ((e: { resultIndex: number; results: ArrayLike<{ isFinal: boolean; 0: { transcript: string } }> }) => void) | null;
  onerror: ((e: { error: string }) => void) | null;
  onend: (() => void) | null;
  start(): void;
  stop(): void;
};

type RecognitionCtor = new () => Recognition;

const Ctor: RecognitionCtor | undefined =
  (window as unknown as { SpeechRecognition?: RecognitionCtor; webkitSpeechRecognition?: RecognitionCtor }).SpeechRecognition ??
  (window as unknown as { webkitSpeechRecognition?: RecognitionCtor }).webkitSpeechRecognition;

export type Lang = "en-US" | "ka-GE";

export function loadLang(): Lang {
  try {
    return localStorage.getItem("liveforge-lang") === "ka-GE" ? "ka-GE" : "en-US";
  } catch {
    return "en-US";
  }
}

export function saveLang(lang: Lang): void {
  try {
    localStorage.setItem("liveforge-lang", lang);
  } catch {
    // Remembering the language is a convenience only.
  }
}

export function useSpeech(lang: Lang, onFinal: (text: string) => void) {
  const [listening, setListening] = useState(false);
  const [interim, setInterim] = useState("");
  const rec = useRef<Recognition | null>(null);
  const final = useRef(onFinal);
  final.current = onFinal;

  const stop = useCallback(() => rec.current?.stop(), []);

  const start = useCallback(() => {
    if (!Ctor || rec.current) return;
    const r = new Ctor();
    r.lang = lang;
    r.interimResults = true;
    r.continuous = false;
    let said = "";
    r.onresult = (e) => {
      let live = "";
      for (let i = e.resultIndex; i < e.results.length; i++) {
        const res = e.results[i]!;
        if (res.isFinal) said += res[0].transcript;
        else live += res[0].transcript;
      }
      setInterim(said + live);
    };
    r.onerror = () => setInterim("");
    r.onend = () => {
      rec.current = null;
      setListening(false);
      setInterim("");
      if (said.trim()) final.current(said.trim());
    };
    rec.current = r;
    setListening(true);
    r.start();
  }, [lang]);

  useEffect(() => () => rec.current?.stop(), []);

  return { supported: !!Ctor, listening, interim, start, stop };
}
