import type { Config } from "tailwindcss";

const config: Config = {
  content: [
    "./app/**/*.{ts,tsx}",
    "./components/**/*.{ts,tsx}",
    "./pages/**/*.{ts,tsx}",
    // if you share UI across packages, include their paths too:
    "../../packages/**/*.{ts,tsx}",
  ],

  // ✅ enable class-based dark mode
  darkMode: "class",

  theme: { extend: {} },
  plugins: [],
};

export default config;
