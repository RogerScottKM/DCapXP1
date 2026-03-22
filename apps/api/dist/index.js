"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const port = Number(process.env.PORT ?? 3001);
const app = createApp();
app.listen(port, () => {
    console.log(`apps/api listening on :${port}`);
});
