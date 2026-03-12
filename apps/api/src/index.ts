import { makeApp } from "./app";

const port = Number(process.env.PORT ?? 3001);
const app = makeApp();

app.listen(port, () => {
  console.log(`apps/api listening on :${port}`);
});
