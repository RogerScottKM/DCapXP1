"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
// apps/api/src/server.ts
require("dotenv/config");
const botFarm_1 = require("./botFarm");
const app_1 = require("./app");
// const PORT = Number(process.env.PORT ?? process.env.API_PORT ?? 4010);
const PORT = Number(process.env.API_PORT ?? process.env.PORT ?? 4010);
const app = (0, app_1.createApp)();
app.listen(PORT, () => {
    console.log(`api listening on ${PORT}`);
    if (process.env.ENABLE_BOT_FARM === "1") {
        (0, botFarm_1.startBotFarm)().catch((e) => console.error("[botFarm]", e));
    }
});
process.on("unhandledRejection", (e) => console.error("unhandledRejection", e));
process.on("uncaughtException", (e) => console.error("uncaughtException", e));
