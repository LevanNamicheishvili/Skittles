import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { App } from "./App.tsx";
import { Docs } from "./Docs.tsx";
import "./styles.css";

// /docs is the documentation; everything else is the landing page and the room.
createRoot(document.getElementById("root")!).render(<StrictMode>{location.pathname.startsWith("/docs") ? <Docs /> : <App />}</StrictMode>);
