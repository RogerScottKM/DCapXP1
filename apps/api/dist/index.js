"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const app_1 = require("./app");
const port = Number(process.env.PORT ?? 3001);
const app = (0, app_1.makeApp)();
app.listen(port, () => {
    console.log(`apps/api listening on :${port}`);
});
