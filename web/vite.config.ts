import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// In development the room server runs on :3000; the client reaches it through this proxy.
// SKITTLES_ROOM points it at another room, e.g. SKITTLES_ROOM=http://localhost:3001 npm run dev.
const room = process.env.SKITTLES_ROOM ?? "http://localhost:3000";

export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    proxy: { "/socket.io": { target: room, ws: true } },
    fs: { allow: [".."] },
  },
});
