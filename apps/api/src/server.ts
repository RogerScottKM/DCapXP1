// apps/api/src/server.ts
import "dotenv/config";
import { startBotFarm } from "./botFarm";
import { createApp } from "./app";


// const PORT = Number(process.env.PORT ?? process.env.API_PORT ?? 4010);
const PORT = Number(process.env.API_PORT ?? process.env.PORT ?? 4010);

const app = createApp();

app.listen(PORT, () => {
  console.log(`api listening on ${PORT}`);
  if (process.env.ENABLE_BOT_FARM === "1") {
    startBotFarm().catch((e) => console.error("[botFarm]", e));
  }
});

process.on("unhandledRejection", (e) => console.error("unhandledRejection", e));
process.on("uncaughtException", (e) => console.error("uncaughtException", e));
