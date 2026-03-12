// apps/web/next.config.mjs
/** @type {import('next').NextConfig} */
const nextConfig = {
  output: "standalone",

  async rewrites() {
    const apiBase =
      process.env.API_INTERNAL_URL ||
      process.env.API_URL ||
      "http://127.0.0.1:4010";

    return [
      // ✅ keep legacy URLs working:
      // /api/stream/BTC-USD -> /api/stream/symbol/BTC-USD
      {
        source: "/api/stream/:symbol",
        destination: "/api/stream/symbol/:symbol",
      },

      // ✅ keep mode URLs working:
      // /api/stream/PAPER/BTC-USD -> /api/stream/mode/PAPER/BTC-USD
      {
        source: "/api/stream/:mode/:symbol",
        destination: "/api/stream/mode/:mode/:symbol",
      },

      // existing proxy rule (unchanged)
      {
        source: "/x/:path*",
        destination: `${apiBase}/:path*`,
      },
    ];
  },
};

export default nextConfig;
