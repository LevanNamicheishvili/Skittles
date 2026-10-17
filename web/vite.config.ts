import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// In development the room server runs on :3000; the client reaches it through this proxy.
export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    proxy: { "/socket.io": { target: "http://localhost:3000", ws: true } },
    fs: { allow: [".."] },
  },
});
