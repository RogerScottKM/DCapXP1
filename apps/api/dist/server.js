"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
require("dotenv/config");
const botFarm_1 = require("./botFarm");
const app_1 = __importDefault(require("./app"));
const PORT = Number(process.env.API_PORT ?? process.env.PORT ?? 4010);
app_1.default.listen(PORT, () => {
    console.log(`api listening on ${PORT}`);
    if (process.env.ENABLE_BOT_FARM === "1") {
        (0, botFarm_1.startBotFarm)().catch((e) => console.error("[botFarm]", e));
    }
});
process.on("unhandledRejection", (e) => console.error("unhandledRejection", e));
process.on("uncaughtException", (e) => console.error("uncaughtException", e));
